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
  householdDnsSettings = lib.custom.dns.resolvedSettings;
  cfg = config.${namespace}.containers.flood;
  completedDir = "/var/lib/torrents/${cfg.completedDirectory}";
  completedDirectory = pkgs.writeShellApplication {
    name = "rtorrent-completed-directory";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      exec python3 ${./completed-directory.py} "$@"
    '';
  };
in
{
  options.${namespace}.containers.flood = with types; {
    enable = mkBoolOpt false "Enable flood nixos-container with rtorrent;";
    dataPath = mkOpt str "/tank/torrents" "Flood data path on host machine";
    completedDirectory =
      mkOpt (strMatching "[a-zA-Z0-9_-]+") "completed"
        "Completed directory name within dataPath; must share the download directory's filesystem";
    host = mkOpt str "flood.sbulav.ru" "The host to serve flood on";
    hostAddress = mkOpt str "172.16.64.10" "With private network, which address to use on Host";
    localAddress = mkOpt str "172.16.64.105" "With privateNetwork, which address to use in container";
  };
  imports = [
    (import ../shared/shared-adguard-dns-rewrite.nix {
      inherit (cfg) host;
      rewrite_enabled = cfg.enable;
    })
  ];

  config = mkIf cfg.enable {
    custom.containers.traefik.routes = {
      flood = {
        inherit (cfg) host;
        url = "http://${cfg.localAddress}:3000";
      };
      "allowedips-flood" = {
        service = "flood";
        inherit (cfg) host;
        url = "http://${cfg.localAddress}:3000";
        middlewares = [
          "secure-headers"
          "allow-lan"
        ];
        clientIPs = [
          "172.16.64.0/24"
          "192.168.89.0/24"
        ];
      };
    };

    networking.nat = {
      enable = true;
      internalInterfaces = [ "ve-flood" ];
      externalInterface = "enp3s0";
    };
    containers.flood = {
      ephemeral = true;
      autoStart = true;

      # Mounting Cloudflare creds(email and dns api token) as file
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
      # Need to add 172.16.64.0/18 on router
      inherit (cfg) hostAddress;
      inherit (cfg) localAddress;

      config = _: {
        systemd.tmpfiles.rules = [
          "d /var/lib/torrents/log 700 rtorrent rtorrent -"
          "d /var/lib/torrents/download 0775 rtorrent rtorrent -"
          "d ${completedDir} 0775 rtorrent rtorrent -"
          "d /run/rtorrent 700 rtorrent rtorrent -"
        ];
        services.rtorrent = {
          enable = true;
          dataDir = "/var/lib/torrents";
          # package = pkgs.jesec-rtorrent;
          # Using upstream rtorrent pkg, config below is required
          # https://github.com/jesec/flood?tab=readme-ov-file#rtorrent-notes

          configText = ''
            method.redirect=load.throw,load.normal
            method.redirect=load.start_throw,load.start
            method.insert=d.down.sequential,value|const,0
            method.insert=d.down.sequential.set,value|const,0

            # Only relocate downloads from the default directory, never custom
            # locations or existing seeds. Keep single- and multi-file torrents
            # seeding at their new path and persist that path across restarts.
            # Unlike d.base_path, this remains valid after d.close. Refuse name
            # collisions and cross-filesystem copies; failure leaves it stopped
            # at the original path instead of silently overwriting other data.
            # Flood stores URI-encoded labels in d.custom1. Resolve one label
            # before stopping; no label means the completed root, ambiguous or unsafe
            # labels fail without moving data. Labels retain their spelling/case.
            method.insert = d.completion_source, simple, "if=(d.is_multi_file),(d.directory),(cat,(d.directory),/,(d.name))"
            method.insert = d.completion_directory, simple, "execute.capture=${lib.getExe completedDirectory},${completedDir},(d.custom1)"
            method.insert = d.move_completed, simple, "d.custom.set=dotnix_completed_directory,(d.completion_directory);d.stop=;d.close=;execute.throw=${pkgs.coreutils}/bin/mv,--no-copy,--update=none-fail,-T,--,(d.completion_source),(cat,(d.custom,dotnix_completed_directory),/,(d.name));d.directory.set=(d.custom,dotnix_completed_directory);d.start=;d.save_full_session="
            method.set_key = event.download.finished,move_completed,"branch=(equal,((d.completion_source)),((cat,/var/lib/torrents/download/,(d.name)))),((d.move_completed))"
          '';
        };
        services.flood = {
          enable = true;
          host = cfg.localAddress;
          port = 3000;
          extraArgs = [
            "--noauth"
            "--rtsocket=${config.services.rtorrent.rpcSocket}"
            "--allowedpath=/var/lib/torrents/"
            "--allowedpath=${completedDir}"
            "--allowedpath=/var/lib/torrents/download"
          ];
        };
        systemd.services.flood = {
          wantedBy = [ "multi-user.target" ];
          wants = [ "rtorrent.service" ];
          after = [ "rtorrent.service" ];
          serviceConfig = {
            User = "rtorrent";
            SupplementaryGroups = [ "rtorrent" ];
            ReadWritePaths = [
              "/var/lib/torrents/download"
              completedDir
            ];
          };
        };

        networking = {
          firewall = {
            enable = true;
            allowedTCPPorts = [ 3000 ];
          };

          useHostResolvConf = false;
        };

        services.resolved = {
          enable = true;
          settings.Resolve = householdDnsSettings;
        };
        system.stateVersion = "24.11";
      };
    };
  };
}
