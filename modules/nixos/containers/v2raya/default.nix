{
  pkgs,
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.${namespace}.containers.v2raya;

  v2rayaPackage = pkgs.v2raya.override { v2ray = pkgs.xray; };

  # domain rules catch RU sites before DNS/CDN can route them abroad;
  # ip(geoip:ru) is the fallback for RU-hosted IPs on other TLDs.
  routingA = ''
    default: proxy
    domain(domain:sbulav.ru, domain:pyn.ru, domain:hhdev.ru)->direct
    domain(geosite:category-ru)->direct
    domain(regexp:\.ru$, regexp:\.su$, regexp:\.xn--p1ai$)->direct
    ip(geoip:private, geoip:ru)->direct
  '';

  # Runs only inside the nixos-container. Talks to v2rayA on localhost.
  bootstrap = pkgs.writeShellApplication {
    name = "v2raya-bootstrap";
    runtimeInputs = with pkgs; [
      curl
      jq
      coreutils
      systemd
    ];
    text = ''
      set -euo pipefail

      API="http://127.0.0.1:2017"
      PASS_FILE="${config.sops.secrets."v2raya/admin_password".path}"
      URIS_FILE="${config.sops.secrets."v2raya/vless_uris".path}"
      ROUTINGA_FILE=/etc/v2raya-bootstrap/routingA.txt

      wait_api() {
        local n=0
        while [[ $n -lt 90 ]]; do
          if curl -fsS "$API/api/version" >/dev/null 2>&1; then
            return 0
          fi
          n=$((n + 1))
          sleep 1
        done
        echo "v2raya API not ready" >&2
        return 1
      }

      # Password goes via --rawfile + stdin, never on argv (/proc/*/cmdline).
      login() {
        local token resp
        resp=$(
          jq -n --rawfile p "$PASS_FILE" \
            '{username:"admin",password:($p|rtrimstr("\n"))}' \
            | curl -sS -X POST "$API/api/login" \
              -H 'Content-Type: application/json' \
              --data @- || true
        )
        token=$(echo "$resp" | jq -r '.data.token // empty' 2>/dev/null || true)
        if [[ -z "$token" || "$token" == "null" ]]; then
          return 1
        fi
        printf '%s' "$token"
      }

      # Wipe bolt DBs so first-time register is allowed again. Paths are the
      # container bind of /tank/v2raya/config — no host network changes.
      # Note: GET /api/account is unreliable across versions; register after wipe.
      reset_accounts() {
        echo "login failed; clearing bolt DBs and re-registering admin"
        systemctl stop --job-mode=replace v2raya.service || true
        sleep 1
        rm -f /etc/v2raya/bolt.db /etc/v2raya/boltv4.db
        rm -f /etc/v2raya/v2raya/bolt.db
        systemctl reset-failed v2raya.service || true
        systemctl start v2raya.service
        wait_api
        local resp code
        resp=$(
          jq -n --rawfile p "$PASS_FILE" \
            '{username:"admin",password:($p|rtrimstr("\n"))}' \
            | curl -sS -X POST "$API/api/account" \
              -H 'Content-Type: application/json' \
              --data @-
        )
        code=$(echo "$resp" | jq -r '.code // empty')
        if [[ "$code" != "SUCCESS" ]]; then
          echo "register failed: $resp" >&2
          return 1
        fi
      }

      auth_curl() {
        local method="$1" path="$2"
        shift 2
        curl -fsS -X "$method" "$API$path" \
          -H "Authorization: Bearer $TOKEN" \
          -H 'Content-Type: application/json' \
          "$@"
      }

      wait_api

      if ! TOKEN=$(login); then
        reset_accounts
        TOKEN=$(login)
      fi
      export TOKEN

      # Drop any existing servers so state matches sops.
      EXISTING=$(auth_curl GET /api/touch)
      TOUCHES=$(echo "$EXISTING" | jq -c '
        [.data.touch.servers[]? | {id, _type}]
        + [.data.touch.subscriptions[]? | {id, _type}]
      ')
      if [[ "$TOUCHES" != "[]" && "$TOUCHES" != "null" ]]; then
        auth_curl DELETE /api/touch -d "$(jq -n --argjson t "$TOUCHES" '{touches:$t}')" >/dev/null
      fi

      # URIs carry endpoint creds: pass via stdin (printf is a builtin), not argv.
      while IFS= read -r uri || [[ -n "$uri" ]]; do
        uri=''${uri%$'\r'}
        [[ -z "$uri" ]] && continue
        printf '%s\n' "$uri" | jq -Rc '{url:.}' \
          | auth_curl POST /api/import --data @- >/dev/null
      done <"$URIS_FILE"

      TOUCH=$(auth_curl GET /api/touch)
      NSERVERS=$(echo "$TOUCH" | jq '.data.touch.servers|length')
      if [[ "$NSERVERS" -lt 1 ]]; then
        echo "no servers imported" >&2
        exit 1
      fi

      # Outbound leastping is set for UI/future; with Xray on v2rayA 2.2.7.x
      # multi-select is not supported (loadBalanceValid=false) — each connect
      # replaces the previous. We still import all three so the UI can switch.
      auth_curl PUT /api/outbound \
        -d "$(jq -n '{
          outbound:"proxy",
          setting:{
            probeURL:"https://www.gstatic.com/generate_204",
            probeInterval:"60s",
            type:"leastping"
          }
        }')" >/dev/null || true

      # Connect last = active primary. Prefer AliceVPN-NL (first in sops list).
      while IFS= read -r which; do
        [[ -z "$which" ]] && continue
        auth_curl POST /api/connection -d "$which" >/dev/null
      done < <(echo "$TOUCH" | jq -c '.data.touch.servers|reverse[]? | {id, _type, outbound:"proxy"}')

      # portSharing=true → SOCKS/HTTP listen on 0.0.0.0 (LAN-reachable via
      # container IP / host forwardPorts). false keeps them on 127.0.0.1 only.
      SETTING=$(auth_curl GET /api/setting | jq '.data.setting')
      auth_curl PUT /api/setting \
        -d "$(echo "$SETTING" | jq '
          .pacMode = "routingA"
          | .transparent = "close"
          | .portSharing = true
        ')" >/dev/null

      auth_curl PUT /api/routingA \
        -d "$(jq -n --arg r "$(cat "$ROUTINGA_FILE")" '{routingA:$r}')" >/dev/null

      auth_curl POST /api/v2ray -d '{}' >/dev/null || true

      CONNECTED=$(auth_curl GET /api/touch | jq '.data.touch.connectedServer|length')
      echo "v2raya bootstrap complete (servers=$NSERVERS connected=$CONNECTED)"
    '';
  };
in
{
  options.${namespace}.containers.v2raya = with types; {
    enable = mkBoolOpt false "Enable v2raya nixos-container;";
    dataPath = mkOpt str "/tank/v2raya" "v2raya data path on host machine";
    host = mkOpt str "v2raya.sbulav.ru" "The host to serve v2raya on";
    hostAddress = mkOpt str "172.16.64.10" "With private network, which address to use on Host";
    localAddress = mkOpt str "172.16.64.108" "With privateNetwork, which address to use in container";
    secret_file = mkOpt str "secrets/zanoza/default.yaml" "SOPS secret file for v2raya credentials";
  };
  imports = [
    (import ../shared/shared-traefik-route.nix {
      app = "v2raya";
      host = cfg.host;
      url = "http://${cfg.localAddress}:2017";
      route_enabled = cfg.enable;
      middlewares = [
        "secure-headers"
        "allow-lan"
      ];
    })
    (import ../shared/shared-adguard-dns-rewrite.nix {
      host = cfg.host;
      rewrite_enabled = cfg.enable;
    })
  ];

  config = mkIf cfg.enable {
    # Secrets are decrypted on the host and bind-mounted into the container.
    # restartUnits: a changed secret must restart the container so bootstrap
    # re-runs and reconciles v2rayA state; fires only on content change.
    custom.security.sops.secrets = {
      "v2raya/admin_password" = {
        sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
        mode = "0400";
        restartUnits = [ "container@v2raya.service" ];
      };
      "v2raya/vless_uris" = {
        sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
        mode = "0400";
        restartUnits = [ "container@v2raya.service" ];
      };
    };

    # Pre-existing host NAT for privateNetwork container egress (unchanged).
    networking.nat = {
      enable = true;
      internalInterfaces = [ "ve-v2raya" ];
      externalInterface = "ens3";
    };

    containers.v2raya = {
      ephemeral = true;
      autoStart = true;
      enableTun = true;

      bindMounts = {
        "/var/log/v2raya/" = {
          hostPath = "${cfg.dataPath}/logs/";
          isReadOnly = false;
        };
        "/etc/v2raya" = {
          hostPath = "${cfg.dataPath}/config";
          isReadOnly = false;
        };
        "${config.sops.secrets."v2raya/admin_password".path}" = {
          isReadOnly = true;
        };
        "${config.sops.secrets."v2raya/vless_uris".path}" = {
          isReadOnly = true;
        };
      };
      privateNetwork = true;
      # Need to add 172.16.64.0/18 on router
      hostAddress = "${cfg.hostAddress}";
      localAddress = "${cfg.localAddress}";

      forwardPorts = [
        {
          containerPort = 20170;
          hostPort = 20170;
          protocol = "tcp";
        }
        {
          containerPort = 20171;
          hostPort = 20171;
          protocol = "tcp";
        }
        {
          containerPort = 20172;
          hostPort = 20172;
          protocol = "tcp";
        }
      ];
      config =
        { ... }:
        {
          environment.etc."v2raya-bootstrap/routingA.txt".text = routingA;

          services.v2raya = {
            enable = true;
            cliPackage = pkgs.xray;
          };

          # Seed geoip/geosite from the store on first boot ("C" copies only if
          # missing); v2rayA can still update them in place afterwards. Without
          # them v2rayA tries to download from GitHub at start and dies when
          # DNS/egress is unavailable (ephemeral container, private network).
          systemd.tmpfiles.rules = [
            "C /etc/v2raya/geoip.dat 0644 - - - ${pkgs.v2ray-geoip}/share/v2ray/geoip.dat"
            "C /etc/v2raya/geosite.dat 0644 - - - ${pkgs.v2ray-domain-list-community}/share/v2ray/geosite.dat"
          ];

          systemd.services.v2raya.serviceConfig = {
            ExecStart = lib.mkForce "${lib.getExe v2rayaPackage} --log-disable-timestamp --v2ray-assetsdir /etc/v2raya --config /etc/v2raya";
            Environment = [
              "V2RAYA_LOG_FILE=/var/log/v2raya/v2raya.log"
              "V2RAY_LOCATION_ASSET=/etc/v2raya"
              "XRAY_LOCATION_ASSET=/etc/v2raya"
            ];
          };

          # After multi-user so nspawn is ready. Do NOT Requires=v2raya: bootstrap
          # may stop/start v2raya for password reset and must not be killed with it.
          systemd.services.v2raya-bootstrap = {
            description = "Configure v2rayA from sops (container-local API)";
            after = [
              "multi-user.target"
              "v2raya.service"
            ];
            wants = [ "v2raya.service" ];
            wantedBy = [ "multi-user.target" ];
            unitConfig = {
              StartLimitIntervalSec = 0;
            };
            # Restart=on-failure is valid for oneshot (systemd >= 244) and makes
            # a failed bootstrap self-heal instead of leaving v2rayA unconfigured.
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              TimeoutStartSec = "300s";
              Restart = "on-failure";
              RestartSec = "30s";
              ExecStart = "${bootstrap}/bin/v2raya-bootstrap";
            };
          };

          networking = {
            enableIPv6 = false;
            firewall = {
              enable = false;
              allowedTCPPorts = [
                2017
                20170
                20171
                20172
              ];
            };
            # Use systemd-resolved inside the container
            # Workaround for bug https://github.com/NixOS/nixpkgs/issues/162686
            useHostResolvConf = lib.mkForce false;
          };
          services.resolved = {
            enable = true;
            settings.Resolve.DNS = "172.16.64.104";
          };
          system.stateVersion = "24.11";
        };
    };
  };
}
