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
  cfg = config.${namespace}.services.prometheus-exporters;
  textfileDirectory = cfg.node.textfile.directory;

  # Publishes zfs-status.prom atomically. The exporter's own success and
  # last-run gauges are always written, so a broken zpool or parser shows up
  # as a failure instead of leaving the previous pool state in place.
  zfsStatusScript = pkgs.writeShellApplication {
    name = "zfs-status-textfile";
    runtimeInputs = [
      pkgs.coreutils
      config.boot.zfs.package
      pkgs.custom.zfs-status-metrics
    ];
    text = ''
      metrics_tmp=$(mktemp ${escapeShellArg textfileDirectory}/.zfs-status.prom.XXXXXX)
      trap 'rm -f "$metrics_tmp"' EXIT
      now=$(date +%s)

      success=1
      if ! zpool status -jp --json-int | zfs-status-metrics >"$metrics_tmp"; then
        echo "zpool status or its parsing failed; publishing success=0" >&2
        success=0
        : >"$metrics_tmp"
      fi
      cat >>"$metrics_tmp" <<EOF
      # HELP zfs_status_exporter_success Whether the last zpool status export succeeded.
      # TYPE zfs_status_exporter_success gauge
      zfs_status_exporter_success $success
      # HELP zfs_status_exporter_last_run_timestamp_seconds Unix time of the last zpool status export attempt.
      # TYPE zfs_status_exporter_last_run_timestamp_seconds gauge
      zfs_status_exporter_last_run_timestamp_seconds $now
      EOF

      chmod 0644 "$metrics_tmp"
      mv -f "$metrics_tmp" ${escapeShellArg "${textfileDirectory}/zfs-status.prom"}
      [ "$success" = 1 ]
    '';
  };
in
{
  options.${namespace}.services.prometheus-exporters = with types; {
    enable = mkBoolOpt false "Enable Prometheus exporters for monitoring";

    node = {
      enable = mkBoolOpt true "Enable Node exporter (CPU, memory, disk, network)";
      port = mkOpt int 9100 "Port for Node exporter";
      openFirewall = mkBoolOpt false "Open firewall for remote scraping";
      # The single owner of --collector.textfile.directory: modules that
      # publish *.prom files enable this instead of adding the flag
      # themselves. Listing the same directory twice makes node_exporter read
      # every file twice and fail each scrape's gather with duplicate series.
      textfile = {
        enable = mkBoolOpt false "Enable the node exporter textfile collector and create its directory";
        directory =
          mkOpt str "/var/lib/node_exporter/textfile_collector"
            "Directory the textfile collector reads *.prom files from";
      };
    };

    smartctl = {
      enable = mkBoolOpt false "Enable Smartctl exporter (disk health)";
      port = mkOpt int 9633 "Port for Smartctl exporter";
      openFirewall = mkBoolOpt false "Open firewall for remote scraping";
      devices = mkOpt (listOf str) [ ] "List of devices to monitor, e.g., ['/dev/nvme0n1']";
    };

    zfsStatus = {
      enable = mkBoolOpt false "Export `zpool status` (vdev errors, scrub/resilver) through the textfile collector";
      interval = mkOpt str "*:0/5" "systemd OnCalendar expression for the zpool status export";
    };
  };

  config = mkMerge [
    # Independent of `enable`: the directory and the flag are what the
    # publishing modules relied on before, whoever enables the node exporter.
    (mkIf cfg.node.textfile.enable {
      services.prometheus.exporters.node.extraFlags = [
        "--collector.textfile.directory=${textfileDirectory}"
      ];
      systemd.tmpfiles.rules = [ "d ${textfileDirectory} 0755 root root -" ];
    })

    (mkIf cfg.enable {
      services.prometheus.exporters = mkMerge [
        (mkIf cfg.node.enable {
          node = {
            enable = true;
            port = cfg.node.port;
            openFirewall = cfg.node.openFirewall;
          };
        })

        (mkIf cfg.smartctl.enable {
          smartctl = {
            enable = true;
            port = cfg.smartctl.port;
            openFirewall = cfg.smartctl.openFirewall;
            devices = cfg.smartctl.devices;
          };
        })
      ];
    })

    (mkIf (cfg.enable && cfg.zfsStatus.enable) {
      ${namespace}.services.prometheus-exporters.node.textfile.enable = true;

      systemd.timers.zfs-status-textfile = {
        description = "Export zpool status to the node exporter";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.zfsStatus.interval;
          Persistent = true;
        };
      };

      # `zpool status` only needs the read-only /dev/zfs ioctls that any user
      # may issue, so root keeps no capabilities beyond owning the directory.
      systemd.services.zfs-status-textfile = {
        description = "Export zpool status to the node exporter";
        after = [ "zfs-import.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = getExe zfsStatusScript;
          UMask = "0022";
          CapabilityBoundingSet = [ "" ];
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ReadWritePaths = [ textfileDirectory ];
          ProtectHome = true;
          PrivateTmp = true;
          PrivateNetwork = true;
          RestrictAddressFamilies = [ "AF_UNIX" ];
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          SystemCallArchitectures = "native";
        };
      };
    })
  ];
}
