# qBittorrent download client for the arr stack (issue #39).
#
# Manual pre-steps on the host (one-time, imperative):
#   zfs create -o mountpoint=/tank/media tank/media
#   zfs create -o mountpoint=/tank/qbittorrent tank/qbittorrent
# Revert: disable this module, then `zfs destroy tank/qbittorrent`.
# Before `zfs destroy tank/media`: also disable sonarr AND clear
# jellyfin's arrLibraryPath (its bind mount keeps the dataset busy),
# rebuild, then destroy.
#
# Torrent peer traffic goes DIRECT (no proxy/VPN) — the VPN provider
# blocks detected torrent traffic. Only indexer/metadata HTTP from
# prowlarr/sonarr goes through the v2raya SOCKS proxy.
#
# Shared media convention (same in sonarr container):
#   host /tank/media  →  container /data
#   downloads: /data/torrents  ·  library: /data/library/{anime,tv}
# Both services run with group `media` (fixed gid 2000) and UMask 0002,
# so sonarr can import qbittorrent's files via hardlinks (single dataset).
{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.${namespace}.containers.qbittorrent;
  mediaGid = 2000;
in
{
  options.${namespace}.containers.qbittorrent = with types; {
    enable = mkBoolOpt false "Enable qbittorrent nixos-container;";
    dataPath = mkOpt str "/tank/qbittorrent" "qBittorrent state path on host machine";
    mediaPath = mkOpt str "/tank/media" "Shared arr media path on host machine";
    host = mkOpt str "qbittorrent.sbulav.ru" "The host to serve qbittorrent on";
    hostAddress = mkOpt str "172.16.64.10" "With private network, which address to use on Host";
    localAddress = mkOpt str "172.16.64.115" "With privateNetwork, which address to use in container";
    webuiPort = mkOpt port 8080 "qBittorrent WebUI port";
    torrentingPort = mkOpt port 56881 "qBittorrent peer port (forwarded from host)";
  };
  imports = [
    (import ../shared/shared-traefik-clientip-route.nix {
      app = "qbittorrent";
      host = cfg.host;
      url = "http://${cfg.localAddress}:8080";
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
      internalInterfaces = [ "ve-qbittorrent" ];
      externalInterface = "enp3s0";
    };

    # Incoming peer connections for seeding reach the container via DNAT.
    networking.firewall.allowedTCPPorts = [ cfg.torrentingPort ];
    networking.firewall.allowedUDPPorts = [ cfg.torrentingPort ];

    # Refuse to start when the tank/media dataset is not mounted — otherwise
    # downloads would silently land on the root filesystem. Directory setup
    # runs only after the condition holds (never on the bare root fs);
    # setgid + group media let sonarr hardlink imports.
    # NOTE: /tank/media must be a single ZFS dataset (hardlinks cannot cross
    # datasets) — see manual pre-steps at the top of this file.
    systemd.services."container@qbittorrent" = {
      unitConfig.ConditionPathIsMountPoint = cfg.mediaPath;
      preStart = ''
        mkdir -p ${cfg.mediaPath}/torrents
        chgrp ${toString mediaGid} ${cfg.mediaPath} ${cfg.mediaPath}/torrents
        chmod 2775 ${cfg.mediaPath} ${cfg.mediaPath}/torrents
      '';
    };

    containers.qbittorrent = {
      ephemeral = true;
      autoStart = true;

      bindMounts = {
        "/var/lib/qBittorrent" = {
          hostPath = "${cfg.dataPath}/";
          isReadOnly = false;
        };
        "/data" = {
          hostPath = "${cfg.mediaPath}/";
          isReadOnly = false;
        };
      };
      privateNetwork = true;
      hostAddress = cfg.hostAddress;
      localAddress = cfg.localAddress;
      forwardPorts = [
        {
          containerPort = cfg.torrentingPort;
          hostPort = cfg.torrentingPort;
          protocol = "tcp";
        }
        {
          containerPort = cfg.torrentingPort;
          hostPort = cfg.torrentingPort;
          protocol = "udp";
        }
      ];

      config =
        { ... }:
        {
          users.groups.media.gid = mediaGid;

          services.qbittorrent = {
            enable = true;
            group = "media";
            webuiPort = cfg.webuiPort;
            torrentingPort = cfg.torrentingPort;
            # NOTE: serverConfig is reinstalled on every service start —
            # preferences changed in the WebUI do not survive a restart,
            # torrents/categories do. Keep durable settings here.
            serverConfig = {
              LegalNotice.Accepted = true;
              BitTorrent.Session = {
                DefaultSavePath = "/data/torrents";
                Port = cfg.torrentingPort;
              };
              Preferences.WebUI = {
                # UIs are only reachable through the LAN-only traefik route
                # (same trust model as flood's --noauth).
                AuthSubnetWhitelistEnabled = true;
                AuthSubnetWhitelist = "172.16.64.0/24, 192.168.80.0/20";
                # Traefik passes Host: ${cfg.host} (passHostHeader);
                # qBittorrent would otherwise reject the proxied requests.
                HostHeaderValidation = false;
              };
            };
          };

          # Group-writable files so sonarr (group media) can import/hardlink.
          systemd.services.qbittorrent.serviceConfig.UMask = "0002";

          networking = {
            firewall = {
              enable = true;
              allowedTCPPorts = [
                cfg.webuiPort
                cfg.torrentingPort
              ];
              allowedUDPPorts = [ cfg.torrentingPort ];
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
