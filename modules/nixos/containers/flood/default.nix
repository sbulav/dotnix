{
  config,
  lib,
  namespace,
  pkgs,
  ...
}:
with lib;
with lib.custom;

let
  cfg = config.${namespace}.containers.flood;
in
{
  options.${namespace}.containers.flood = with types; {
    enable = mkBoolOpt false "Enable flood nixos-container with rtorrent;";
    dataPath = mkOpt str "/tank/torrents" "Flood data path on host machine";
    host = mkOpt str "flood.sbulav.ru" "The host to serve flood on";
    hostAddress = mkOpt str "172.16.64.10" "With private network, which address to use on Host";
    localAddress = mkOpt str "172.16.64.105" "With privateNetwork, which address to use in container";
  };

  imports = [
    (import ../shared/shared-traefik-clientip-route.nix {
      app = "flood";
      host = cfg.host;
      url = "http://${cfg.localAddress}:3000";
      route_enabled = cfg.enable;
      middleware = [
        "secure-headers"
        "allow-lan"
      ];
      clientips = "ClientIP(`172.16.64.0/24`) || ClientIP(`192.168.89.0/24`)";
    })
    (import ../shared/shared-traefik-route.nix {
      app = "flood";
      host = cfg.host;
      url = "http://${cfg.localAddress}:3000";
      route_enabled = cfg.enable;
    })
    (import ../shared/shared-adguard-dns-rewrite.nix {
      host = cfg.host;
      rewrite_enabled = cfg.enable;
    })
  ];

  config = mkIf cfg.enable {
    networking.nat = {
      enable = true;
      internalInterfaces = [ "ve-flood" ];
      externalInterface = "ens3";
    };

    containers.flood = {
      ephemeral = true;
      autoStart = true;

      bindMounts = {
        "/var/lib/torrents/log/" = {
          hostPath = "${cfg.dataPath}/log/";
          isReadOnly = false;
        };
        "/var/lib/torrents/" = {
          hostPath = "${cfg.dataPath}/";
          isReadOnly = false;
        };
      };

      privateNetwork = true;
      hostAddress = cfg.hostAddress;
      localAddress = cfg.localAddress;

      config =
        {
          pkgs,
          lib,
          config,
          ...
        }:
        {
          systemd.tmpfiles.rules = [
            "d /var/lib/torrents/log 700 rtorrent rtorrent -"
            "d /var/lib/torrents/session 700 rtorrent rtorrent -"
          ];

          ##################################################################
          # rTorrent configuration
          ##################################################################
          services.rtorrent = {
            enable = true;
            dataDir = "/var/lib/torrents";

            # NEW: move socket to shared persistent directory
            rpcSocket = "/var/lib/torrents/rtorrent.sock";

            # Keep same config text as before
            configText = ''
              method.redirect=load.throw,load.normal
              method.redirect=load.start_throw,load.start
              method.insert=d.down.sequential,value|const,0
              method.insert=d.down.sequential.set,value|const,0
            '';
          };

          ##################################################################
          # Flood configuration
          ##################################################################
          services.flood = {
            enable = true;
            host = cfg.localAddress;
            port = 3000;

            # Updated to use new socket path
            extraArgs = [
              "--noauth"
              "--rtsocket=/var/lib/torrents/rtorrent.sock"
              "--allowedpath=/var/lib/torrents/"
              "--allowedpath=/var/lib/torrents/completed"
              "--allowedpath=/var/lib/torrents/download"
              "--verbose"
            ];
          };

          ##################################################################
          # Fix Flood service permissions
          ##################################################################
          systemd.services.flood = {
            wantedBy = [ "multi-user.target" ];
            wants = [ "rtorrent.service" ];
            after = [ "rtorrent.service" ];

            serviceConfig = {
              User = "rtorrent";
              Group = "rtorrent";
              SupplementaryGroups = [ "rtorrent" ];
              ReadWritePaths = [
                "/var/lib/torrents"
                "/var/lib/torrents/download"
                "/var/lib/torrents/completed"
              ];
            };
          };

          ##################################################################
          # Networking and system settings
          ##################################################################
          networking = {
            firewall = {
              enable = true;
              allowedTCPPorts = [
                3000
                139
                445
              ];
              allowedUDPPorts = [
                137
                138
              ];
            };

            useHostResolvConf = lib.mkForce false;
          };

          services.resolved = {
            enable = true;
            extraConfig = ''
              DNS=172.16.64.104
            '';
          };

          system.stateVersion = "24.11";
        };
    };
  };
}
