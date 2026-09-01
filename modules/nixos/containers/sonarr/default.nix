# Sonarr series/anime automation for the arr stack (issue #39).
#
# Manual pre-steps on the host (one-time, imperative):
#   zfs create -o mountpoint=/tank/media tank/media    # if not created yet
#   zfs create -o mountpoint=/tank/sonarr tank/sonarr
# Revert: disable this module, then `zfs destroy tank/sonarr`.
# Before `zfs destroy tank/media`: also disable qbittorrent AND clear
# jellyfin's arrLibraryPath (its bind mount keeps the dataset busy),
# rebuild, then destroy.
#
# Shared media convention (same in qbittorrent container):
#   host /tank/media  →  container /data
#   downloads: /data/torrents  ·  library: /data/library/{anime,tv}
# Identical paths in both containers mean no "remote path mapping" is
# needed in sonarr, and imports are hardlinks (one dataset, group media,
# UMask 0002).
#
# Metadata/indexer egress goes through the sing-box SOCKS proxy.
# NOTE: *arr proxy settings live in the app database and are
# configurable only via the UI (the SONARR__PROXY__* env vars cover
# config.xml settings only and do NOT work) — one-time wiring:
#   Settings → General → Proxy: SOCKS5 172.16.64.108:20170,
#   Ignored: localhost,127.0.0.1,172.16.64.0/24,192.168.80.0/20
# Calls to prowlarr/qbittorrent bypass it (local addresses).
{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.${namespace}.containers.sonarr;
  mediaGid = 2000;
in
{
  options.${namespace}.containers.sonarr = with types; {
    enable = mkBoolOpt false "Enable sonarr nixos-container;";
    dataPath = mkOpt str "/tank/sonarr" "Sonarr state path on host machine";
    mediaPath = mkOpt str "/tank/media" "Shared arr media path on host machine";
    host = mkOpt str "sonarr.sbulav.ru" "The host to serve sonarr on";
    hostAddress = mkOpt str "172.16.64.10" "With private network, which address to use on Host";
    localAddress = mkOpt str "172.16.64.114" "With privateNetwork, which address to use in container";
  };
  imports = [
    (import ../shared/shared-traefik-clientip-route.nix {
      app = "sonarr";
      host = cfg.host;
      url = "http://${cfg.localAddress}:8989";
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
      internalInterfaces = [ "ve-sonarr" ];
      externalInterface = "enp3s0";
    };

    # Refuse to start when the tank/media dataset is not mounted — otherwise
    # imports would silently land on the root filesystem. Library layout is
    # created only after the condition holds (qbittorrent module owns the
    # /tank/media root and torrents/).
    systemd.services."container@sonarr" = {
      unitConfig.ConditionPathIsMountPoint = cfg.mediaPath;
      preStart = ''
        mkdir -p ${cfg.mediaPath}/library/anime ${cfg.mediaPath}/library/tv
        chgrp ${toString mediaGid} ${cfg.mediaPath}/library ${cfg.mediaPath}/library/anime ${cfg.mediaPath}/library/tv
        chmod 2775 ${cfg.mediaPath}/library ${cfg.mediaPath}/library/anime ${cfg.mediaPath}/library/tv
      '';
    };

    containers.sonarr = {
      ephemeral = true;
      autoStart = true;

      bindMounts = {
        "/var/lib/sonarr" = {
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

      config =
        { ... }:
        {
          users.groups.media.gid = mediaGid;

          services.sonarr = {
            enable = true;
            group = "media";
          };

          # Group-writable imports so jellyfin can read and future arr
          # members can upgrade/replace files (upstream hardcodes 0022).
          systemd.services.sonarr.serviceConfig.UMask = lib.mkForce "0002";

          networking = {
            firewall = {
              enable = true;
              allowedTCPPorts = [ 8989 ];
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
