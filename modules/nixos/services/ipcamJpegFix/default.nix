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
  cfg = config.${namespace}.services.ipcamJpegFix;
in
{
  options.${namespace}.services.ipcamJpegFix = with types; {
    enable = mkBoolOpt false "Enable periodic JPEG fixing via jpegtran to correct IP-camera proprietary bits";
  };

  config = mkIf cfg.enable {
    # Install libjpeg which provides jpegtran
    environment.systemPackages = with pkgs; [
      libjpeg_turbo
    ];

    systemd.timers."ipcam-jpegfix" = {
      description = "Fix IP-camera JPEG files every 10 minutes";
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "10min";
        Persistent = true;
      };
      wantedBy = [ "timers.target" ];
    };

    systemd.services."ipcam-jpegfix" = {
      description = "Convert IP-camera JPEG files with jpegtran to fix proprietary bits";
      # this script runs as root once per timer tick
      script = ''
        #!/usr/bin/env bash
        set -euo pipefail

        # Initialize counters
        processed=0
        converted=0
        failed=0

        # Find all JPEG files modified in the last 30 minutes
        while IFS= read -r jpgfile; do
          processed=$((processed + 1))

          # Skip if file is empty (shouldn't happen but be safe)
          if [ ! -s "$jpgfile" ]; then
            echo "Warning: Skipping empty file: $jpgfile"
            failed=$((failed + 1))
            continue
          fi

          tmpfile="''${jpgfile}.tmp"

          # Run jpegtran and capture exit code
          if ${pkgs.libjpeg_turbo}/bin/jpegtran -copy none "''${jpgfile}" > "''${tmpfile}" 2>/dev/null; then
            mv "''${tmpfile}" "''${jpgfile}"
            converted=$((converted + 1))
          else
            exitcode=$?
            # Treat 0 and 2 as OK; 2 = "file already optimal"
            if [ "$exitcode" -eq 2 ]; then
              # echo "Info: jpegtran reported already optimal: $jpgfile"
              mv "''${tmpfile}" "''${jpgfile}"
              converted=$((converted + 1))
            fi

            # Any other exit code is failure
            rm -f "''${tmpfile}"
            failed=$((failed + 1))
          fi
        done < <(find /tank/ipcam/hcam -type f \( -name '*.jpg' -o -name '*.jpeg' \) -mmin -30 || true)

        # Print summary
        echo "JPEG Fix Summary:"
        echo "  Processed: $processed files"
        echo "  Converted: $converted files"
        echo "  Failed:    $failed files"
      '';
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
    };
  };
}
