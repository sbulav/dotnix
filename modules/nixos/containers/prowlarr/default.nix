# Prowlarr indexer manager for the arr stack (issue #39).
#
# Manual pre-step on the host (one-time, imperative):
#   zfs create -o mountpoint=/tank/prowlarr tank/prowlarr
# Revert: disable this module, then `zfs destroy tank/prowlarr`.
#
# All outbound indexer/metadata traffic goes through the v2raya SOCKS
# proxy. NOTE: *arr proxy settings live in the app database and are
# configurable only via the UI (the PROWLARR__PROXY__* env vars cover
# config.xml settings only and do NOT work) — one-time wiring:
#   Settings → General → Proxy: SOCKS5 172.16.64.108:20170,
#   Ignored: localhost,127.0.0.1,172.16.64.0/24,192.168.80.0/20
# Torrent peer traffic never touches prowlarr — it only hands
# .torrent/magnets over.
{
  config,
  lib,
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
