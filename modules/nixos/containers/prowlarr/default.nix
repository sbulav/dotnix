# Prowlarr indexer manager for the arr stack (issue #39).
#
# Manual pre-step on the host (one-time, imperative):
#   zfs create -o mountpoint=/tank/prowlarr tank/prowlarr
# Revert: disable this module, then `zfs destroy tank/prowlarr`.
#
# All outbound indexer/metadata traffic goes through the sing-box SOCKS
# proxy. NOTE: *arr proxy settings live in the app database and are
# configurable only via the UI (the PROWLARR__PROXY__* env vars cover
# config.xml settings only and do NOT work) — one-time wiring:
#   Settings → General → Proxy: SOCKS5 172.16.64.108:20170,
#   Ignored: localhost,127.0.0.1,172.16.64.0/24,192.168.80.0/20,*.sbulav.ru,
#            torrentio.strem.fun
# (torrentio must bypass the proxy: the sing-box exit IP gets a hard
# Cloudflare 403, while direct access from home works. The direct path
# is RKN-throttled though — Cloudflare TLS streams stall after ~12-16 KB
# — so torrentio.yml pins "|limit=2" in default_opts to keep responses
# ~6-8 KB; without it popular titles die with "ResponseEnded".)
# When FlareSolverr is enabled, add it in Prowlarr as an Indexer Proxy at
# http://127.0.0.1:8191 with a dedicated tag, then apply the same tag only
# to Cloudflare-protected indexers. Prowlarr forwards its global SOCKS proxy
# to FlareSolverr, preserving the sing-box egress path.
# Torrent peer traffic never touches prowlarr — it only hands
# .torrent/magnets over.
#
# Custom Cardigann definitions (*.yml next to this file) are symlinked
# into {dataDir}/Definitions/Custom at container boot; Prowlarr picks
# them up on start. Installing the definition only makes the indexer
# *available* — add it once via UI: Indexers → Add → search "Torrentio".
#
# enableFilmix runs the filmix-torznab bridge (pkgs.custom.filmix-torznab)
# on 127.0.0.1:9117 inside the container. It needs a "filmix-env" sops
# secret shaped as an env file:
#   FILMIX_COOKIE=dle_user_id=NNN; dle_password=HEXHASH
# (long-lived "remember me" DLE cookies, copied from a logged-in browser;
# add HTTPS_PROXY=socks5h://... there if filmix must egress via sing-box).
# One-time UI step: Indexers → Add → Generic Torznab,
# URL http://127.0.0.1:9117, API path /api, no API key.
{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.${namespace}.containers.prowlarr;
in
{
  options.${namespace}.containers.prowlarr = with types; {
    enable = mkBoolOpt false "Enable prowlarr nixos-container;";
    enableFlareSolverr = mkBoolOpt false "Enable FlareSolverr alongside Prowlarr for protected indexers";
    enableFilmix = mkBoolOpt false "Run the filmix-torznab bridge alongside Prowlarr";
    secret_file = mkOpt str "secrets/zanoza/default.yaml" "SOPS file with the filmix-env secret";
    dataPath = mkOpt str "/tank/prowlarr" "Prowlarr state path on host machine";
    host = mkOpt str "prowlarr.sbulav.ru" "The host to serve prowlarr on";
    hostAddress = mkOpt str "172.16.64.10" "With private network, which address to use on Host";
    localAddress = mkOpt str "172.16.64.113" "With privateNetwork, which address to use in container";
  };
  imports = [
    (import ../shared/shared-traefik-clientip-route.nix {
      app = "prowlarr";
      host = cfg.host;
      url = "http://${cfg.localAddress}:9696";
      route_enabled = cfg.enable;
      middleware = [
        "secure-headers"
        "allow-lan"
      ];
      clientips = "ClientIP(`172.16.64.0/24`) || ClientIP(`192.168.80.0/20`)";
    })
    (import ../shared/shared-adguard-dns-rewrite.nix {
      host = cfg.host;
      rewrite_enabled = cfg.enable;
    })
  ];

  config = mkIf cfg.enable {
    networking.nat = {
      enable = true;
      internalInterfaces = [ "ve-prowlarr" ];
      externalInterface = "enp3s0";
    };

    custom.security.sops.secrets = mkIf cfg.enableFilmix {
      "filmix-env" = lib.custom.secrets.containers.envFileWithRestart "prowlarr" // {
        sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
      };
    };

    containers.prowlarr = {
      ephemeral = true;
      autoStart = true;

      bindMounts = {
        # The module bind-mounts this custom dataDir onto
        # /var/lib/private/prowlarr (DynamicUser + StateDirectory).
        "/var/lib/prowlarr-data" = {
          hostPath = "${cfg.dataPath}/";
          isReadOnly = false;
        };
      }
      // lib.optionalAttrs cfg.enableFilmix {
        "${config.sops.secrets."filmix-env".path}" = {
          isReadOnly = true;
        };
      };
      privateNetwork = true;
      hostAddress = cfg.hostAddress;
      localAddress = cfg.localAddress;

      config =
        { ... }:
        {
          services.prowlarr = {
            enable = true;
            dataDir = "/var/lib/prowlarr-data";
          };

          services.flaresolverr.enable = cfg.enableFlareSolverr;

          systemd.services.prowlarr = lib.mkMerge [
            {
              # Cardigann custom definitions, declaratively. Installed from
              # preStart (not tmpfiles): the data dir belongs to prowlarr's
              # DynamicUser, so root-driven tmpfiles trips the "unsafe path
              # transition" check on the bind-mounted dataset. Must go
              # through $STATE_DIRECTORY — the raw /var/lib/prowlarr-data
              # path is read-only inside the service sandbox.
              preStart = ''
                install -D -m0644 ${./torrentio.yml} \
                  "$STATE_DIRECTORY/Definitions/Custom/torrentio.yml"
              '';
            }
            (lib.mkIf cfg.enableFlareSolverr {
              after = [ "flaresolverr.service" ];
              wants = [ "flaresolverr.service" ];
            })
          ];

          # Torznab bridge for Filmix PRO+ (see header). Loopback only:
          # nothing but Prowlarr in this container ever talks to it.
          systemd.services.filmix-torznab = lib.mkIf cfg.enableFilmix {
            description = "Filmix Torznab bridge";
            wantedBy = [ "multi-user.target" ];
            after = [ "network.target" ];
            serviceConfig = {
              ExecStart = lib.getExe pkgs.custom.filmix-torznab;
              EnvironmentFile = config.sops.secrets."filmix-env".path;
              DynamicUser = true;
              Restart = "on-failure";
              RestartSec = 10;
              # Hardening: it only needs outbound HTTP and a loopback socket.
              NoNewPrivileges = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              PrivateTmp = true;
              CapabilityBoundingSet = "";
            };
          };

          networking = {
            firewall = {
              enable = true;
              allowedTCPPorts = [ 9696 ];
            };
            useHostResolvConf = lib.mkForce false;
          };

          services.resolved = {
            enable = true;
            settings.Resolve.DNS = "172.16.64.104";
          };
          system.stateVersion = "26.05";
        };
    };
  };
}
