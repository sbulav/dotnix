{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.${namespace}.services.ipcamCleanup;
in
{
  options.${namespace}.services.ipcamCleanup = with types; {
    enable = mkBoolOpt false "Enable hourly cleanup of /tank/ipcam and .dav→.dav.mp4 hardlinks";
  };

  config = mkIf cfg.enable {
    systemd.timers."ipcam-cleanup" = {
      description = "Hourly cleanup of old IP-cam folders and .dav→.dav.mp4 linking";
      timerConfig = {
        OnCalendar = "hourly";
        Persistent = true;
      };
      wantedBy = [ "timers.target" ];
    };

    systemd.services."ipcam-cleanup" = {
      description = "Remove /tank/ipcam/hcam subdirs older than 30 days; link .dav→.dav.mp4";
      script = ''
        #!/usr/bin/env bash
        set -euxo pipefail

        # 1) delete any top-level folder older than 30d
        find /tank/ipcam/hcam \
          -mindepth 1 -maxdepth 1 \
          -type d -mtime +30 \
          -exec rm -rf {} +

        # 2) for every .dav file, ensure a .dav.mp4 hardlink exists
        find /tank/ipcam/hcam -type f -name '*.dav' | while IFS= read -r f; do
          # escape '$_{f}' as $${f} so Nix leaves it alone
          link="''${f}.mp4"
          [ -e "$link" ] || ln "$f" "$link"
        done
      '';
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        # Root only for the capabilities below: the camera files are owned by
        # nobody (NFS-squashed), not all dirs are world-writable, and
        # fs.protected_hardlinks gates linking files we do not own.
        CapabilityBoundingSet = [
          "CAP_CHOWN"
          "CAP_DAC_OVERRIDE"
          "CAP_FOWNER"
        ];
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ "/tank/ipcam/hcam" ];
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        PrivateNetwork = true;
        RestrictAddressFamilies = [ "none" ];
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProcSubset = "pid";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" ];
      };
    };
  };
}
