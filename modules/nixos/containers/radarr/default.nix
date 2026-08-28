# Radarr movie automation for the arr stack (issue #39).
#
# Manual pre-steps on the host (one-time, imperative):
#   zfs create -o mountpoint=/tank/media tank/media    # if not created yet
#   zfs create -o mountpoint=/tank/radarr tank/radarr
# Revert: disable this module, then `zfs destroy tank/radarr`.
# Before `zfs destroy tank/media`: also disable qbittorrent AND clear
# jellyfin's arrLibraryPath (its bind mount keeps the dataset busy),
# rebuild, then destroy.
#
# Shared media convention (same in sonarr/qbittorrent containers):
#   host /tank/media  →  container /data
#   downloads: /data/torrents  ·  library: /data/library/movies
# Identical paths in both containers mean no "remote path mapping" is
# needed in radarr, and imports are hardlinks (one dataset, group media,
# UMask 0002).
#
# Metadata/indexer egress goes through the v2raya SOCKS proxy.
# NOTE: *arr integration settings live in the app database and are
# configurable only via the UI or HTTP API (the RADARR__* env vars cover
# config.xml settings only and do NOT work) — one-time wiring, doable via
# the API with the key from <dataPath>/config.xml:
#   - Settings → General → Proxy: SOCKS5 172.16.64.108:20170,
#     Ignored: localhost,127.0.0.1,172.16.64.0/24,192.168.80.0/20
#     (calls to prowlarr/qbittorrent bypass it — local addresses)
#   - Root folder: /data/library/movies
#   - Download client: qBittorrent 172.16.64.115:8080, category "radarr"
#     (no credentials — its WebUI auth whitelists 172.16.64.0/24)
#   - Russian-audio preference: custom formats "RU audio (language)" and
#     "RU audio (title markers)" scored +1000 in the quality profile,
#     minFormatScore 0 — prefer Russian, fall back to any language,
#     upgrade when a Russian release shows up later. The profile's
#     Language must be "Any": the default "Original" hard-rejects every
#     Russian-dub release before scoring even happens
#   - Prowlarr → Settings → Apps → add Radarr (full sync) so the existing
#     indexers propagate automatically. Sync Categories must include
#     8000 (Other) besides the 2000 movie tree: RuTor returns every
#     result as 8000/"Other" (stated in its Prowlarr definition), so
#     without it Prowlarr refuses to sync RuTor ("no results in the
#     configured categories")
#
# maxReleaseSizeGB caps release size (Settings → Indexers → Maximum Size).
# Unlike the wiring above it is NOT a one-time UI step: an
# `radarr-api-settings` oneshot reapplies it over the API on every container
# start, so Nix owns that one key and the UI cannot win. Prowlarr has no
# equivalent knob — the cap has to live here, in the app that decides what
# to grab. It is a Permanent rejection, so it also blocks force-grabs from
# automatic search; interactive search still shows the release, greyed out.
# The cap only gates NEW grabs — use `radarr-requeue` on the host to kick
# already-running oversized downloads back out for a smaller release.
# Torrent peer traffic never touches radarr — qbittorrent handles it.
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
  cfg = config.${namespace}.containers.radarr;
  mediaGid = 2000;
in
{
  options.${namespace}.containers.radarr = with types; {
    enable = mkBoolOpt false "Enable radarr nixos-container;";
    dataPath = mkOpt str "/tank/radarr" "Radarr state path on host machine";
    mediaPath = mkOpt str "/tank/media" "Shared arr media path on host machine";
    maxReleaseSizeGB =
      mkOpt int 0
        "Reject releases larger than this many GiB (Settings → Indexers → Maximum Size); 0 = unlimited";
    host = mkOpt str "radarr.sbulav.ru" "The host to serve radarr on";
    hostAddress = mkOpt str "172.16.64.10" "With private network, which address to use on Host";
    localAddress = mkOpt str "172.16.64.116" "With privateNetwork, which address to use in container";
  };
  imports = [
    (import ../shared/shared-traefik-clientip-route.nix {
      app = "radarr";
      host = cfg.host;
      url = "http://${cfg.localAddress}:7878";
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
      internalInterfaces = [ "ve-radarr" ];
      externalInterface = "enp3s0";
    };

    # `radarr-requeue` — kick oversized in-flight downloads out of the
    # queue so radarr re-grabs them under the size cap (the cap itself only
    # applies to new grabs).
    environment.systemPackages = [
      (import ../shared/shared-arr-requeue.nix {
        inherit pkgs lib;
        app = "radarr";
        url = "http://${cfg.localAddress}:7878";
        configXml = "${cfg.dataPath}/.config/Radarr/config.xml";
        queueParams = "includeUnknownMovieItems=true&includeMovie=true";
        defaultMaxGB = cfg.maxReleaseSizeGB;
      })
    ];

    # Refuse to start when the tank/media dataset is not mounted — otherwise
    # imports would silently land on the root filesystem. Library layout is
    # created only after the condition holds (qbittorrent module owns the
    # /tank/media root and torrents/).
    systemd.services."container@radarr" = {
      unitConfig.ConditionPathIsMountPoint = cfg.mediaPath;
      preStart = ''
        mkdir -p ${cfg.mediaPath}/library/movies
        chgrp ${toString mediaGid} ${cfg.mediaPath}/library ${cfg.mediaPath}/library/movies
        chmod 2775 ${cfg.mediaPath}/library ${cfg.mediaPath}/library/movies
      '';
    };

    containers.radarr = {
      ephemeral = true;
      autoStart = true;

      bindMounts = {
        "/var/lib/radarr" = {
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
          imports = [
            # Maximum Size lives in the app database, so it can only be set
            # over the API — this reapplies it on every container start.
            (import ../shared/shared-arr-api-settings.nix {
              app = "radarr";
              port = 7878;
              configXml = "/var/lib/radarr/.config/Radarr/config.xml";
              settings.indexer.maximumSize = cfg.maxReleaseSizeGB * 1024;
            })
          ];

          users.groups.media.gid = mediaGid;

          services.radarr = {
            enable = true;
            group = "media";
          };

          # Group-writable imports so jellyfin can read and future arr
          # members can upgrade/replace files (upstream hardcodes 0022).
          systemd.services.radarr.serviceConfig.UMask = lib.mkForce "0002";

          networking = {
            firewall = {
              enable = true;
              allowedTCPPorts = [ 7878 ];
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
