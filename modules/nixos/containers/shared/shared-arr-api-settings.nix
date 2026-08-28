# Applies *arr settings that live in the application database and are
# therefore reachable only over the HTTP API — the SONARR__*/RADARR__*
# env vars cover config.xml settings only and do NOT work (see the arr
# module headers).
#
# Idempotent, runs on every container start: reads the current config
# resource, shallow-merges the wanted attrs, PUTs only on drift. Nix wins
# over the UI for the keys named here; everything else stays UI-owned.
#
# Instantiate from inside a container's `config`:
#   imports = [
#     (import ../shared/shared-arr-api-settings.nix {
#       app = "radarr";
#       port = 7878;
#       configXml = "/var/lib/radarr/.config/Radarr/config.xml";
#       settings.indexer.maximumSize = 10240;   # MiB, 0 = unlimited
#     })
#   ];
{
  app,
  service ? app,
  port,
  configXml,
  apiVersion ? "v3",
  settings,
}:
{
  pkgs,
  lib,
  ...
}:
{
  systemd.services."${app}-api-settings" = {
    description = "Apply ${app} database-only settings over its HTTP API";
    wantedBy = [ "multi-user.target" ];
    after = [ "${service}.service" ];
    wants = [ "${service}.service" ];
    path = [
      pkgs.curl
      pkgs.jq
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # The retry loops below wait out a slow first start (schema
      # migrations), well past DefaultTimeoutStartSec.
      TimeoutStartSec = 600;
      Restart = "on-failure";
      RestartSec = 30;
    };
    script = ''
      api="http://127.0.0.1:${toString port}/api/${apiVersion}"
      config_xml=${lib.escapeShellArg configXml}

      # config.xml — and the API key inside it — is written on first start.
      for _ in $(seq 1 150); do
        if [ -s "$config_xml" ]; then break; fi
        sleep 2
      done
      key=$(sed -n 's|.*<ApiKey>\(.*\)</ApiKey>.*|\1|p' "$config_xml")
      if [ -z "$key" ]; then
        echo "no <ApiKey> in $config_xml — giving up" >&2
        exit 1
      fi

      for _ in $(seq 1 150); do
        if curl -sf -o /dev/null -H "X-Api-Key: $key" "$api/system/status"; then break; fi
        sleep 2
      done

      apply() {
        resource="$1"
        want="$2"
        cur=$(curl -sfS -H "X-Api-Key: $key" "$api/config/$resource")
        new=$(jq -c --argjson want "$want" '. * $want' <<<"$cur")
        if [ "$(jq -cS . <<<"$cur")" = "$(jq -cS . <<<"$new")" ]; then
          echo "config/$resource: already $want"
          return 0
        fi
        # RestPutById — the resource id (always 1 for config singletons)
        # is part of the route.
        curl -sfS -o /dev/null -X PUT \
          -H "X-Api-Key: $key" -H "Content-Type: application/json" \
          -d "$new" "$api/config/$resource/$(jq -r '.id' <<<"$new")"
        echo "config/$resource: applied $want"
      }

      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          resource: attrs:
          "apply ${lib.escapeShellArg resource} ${lib.escapeShellArg (builtins.toJSON attrs)}"
        ) settings
      )}
    '';
  };
}
