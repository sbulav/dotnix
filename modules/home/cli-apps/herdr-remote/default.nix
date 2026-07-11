# herdr-remote: monitor and control herdr agents from a phone browser
# (https://github.com/dcolinmorgan/herdr-remote).
#
# Two systemd user services (manual-start unless autoStart is set):
#   systemctl --user start herdr-relay   # WebSocket relay on :8375
#   systemctl --user start herdr-web     # static web app on :8080
# Phone on LAN: open http://<host>:8080, enter ws://<host>:8375 as relay URL.
# Remote: served via Traefik on zanoza as herdr.sbulav.ru / herdr-relay.sbulav.ru
# behind Authelia (see modules/nixos/containers/herdr-remote).
#
# Notes / accepted risks:
# - Token auth (enableTokenAuth): the relay requires the sops-managed shared
#   token (secrets/sab, key herdr_relay_token) on every connection. Disabled
#   on mz — Authelia guards the Traefik path instead; the LAN-direct ports
#   are accepted as open. Retrieve the token (if re-enabled) with:
#     sops -d --extract '["herdr_relay_token"]' secrets/sab/default.yaml
# - Without autoStart, user services die on logout unless linger is enabled.
# - The hosted PWA (herdr-remote.pages.dev) can NOT be used: on the LAN,
#   HTTPS pages are blocked from opening insecure ws:// connections; via
#   Traefik, Authelia's cookie is not sent cross-site. Use the self-hosted app.
{
  inputs,
  pkgs,
  config,
  lib,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.cli-apps.herdr-remote;
  herdrBin = "${inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.herdr}/bin/herdr";
in
{
  options.custom.cli-apps.herdr-remote = {
    enable = mkBoolOpt false "Whether to enable the herdr-remote relay and web app services.";
    relayPort = mkOpt types.port 8375 "WebSocket port of the herdr-remote relay.";
    webPort = mkOpt types.port 8080 "HTTP port serving the herdr-remote web app.";
    enableTokenAuth = mkBoolOpt true "Whether to require a shared token (from sops) for relay connections.";
    autoStart = mkBoolOpt false "Whether to start the relay and web app services automatically (requires linger to survive logout).";
  };

  config = mkIf cfg.enable {
    sops.secrets.herdr_relay_token = mkIf cfg.enableTokenAuth {
      sopsFile = lib.snowfall.fs.get-file "secrets/sab/default.yaml";
    };

    systemd.user.services = {
      herdr-relay = {
        Unit = {
          Description = "herdr-remote relay (WebSocket bridge to herdr agents)";
        };
        Service = {
          # Wrapper reads the token at runtime so it never lands in the nix
          # store or in `systemctl show` output.
          ExecStart = pkgs.writeShellScript "herdr-relay-start" ''
            ${optionalString cfg.enableTokenAuth ''
              export HERDR_RELAY_TOKEN="$(cat ${config.sops.secrets.herdr_relay_token.path})"
            ''}
            exec ${getExe pkgs.custom.herdr-relay}
          '';
          Environment = [
            "HERDR_BIN=${herdrBin}"
            "HERDR_RELAY_PORT=${toString cfg.relayPort}"
          ];
          Restart = "on-failure";
        };
        Install = mkIf cfg.autoStart {
          WantedBy = [ "default.target" ];
        };
      };

      herdr-web = {
        Unit = {
          Description = "herdr-remote web app (static HTTP server)";
        };
        Service = {
          ExecStart = "${pkgs.python3}/bin/python3 -m http.server ${toString cfg.webPort} --directory ${inputs.herdr-remote}/web";
          Restart = "on-failure";
        };
        Install = mkIf cfg.autoStart {
          WantedBy = [ "default.target" ];
        };
      };
    };
  };
}
