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
        # Use process substitution to avoid subshell scope issues with variable assignments
        while IFS= read -r jpgfile; do
          ((processed++))

          # Skip if file is empty (shouldn't happen but be safe)
          if [ ! -s "$jpgfile" ]; then
            echo "Warning: Skipping empty file: $jpgfile"
            ((failed++))
            continue
          fi

          tmpfile="''${jpgfile}.tmp"

          # Convert with jpegtran to fix proprietary bits
          # -copy none: strips all non-essential markers
          if ${pkgs.libjpeg_turbo}/bin/jpegtran -copy none "''${jpgfile}" > "''${tmpfile}" 2>/dev/null; then
            # Move temp file over original
            mv "''${tmpfile}" "''${jpgfile}"
            ((converted++))
          else
            # Clean up temp file on error
            rm -f "''${tmpfile}"
            ((failed++))
          fi
        done < <(find /tank/ipcam/hcam -type f \( -name '*.jpg' -o -name '*.jpeg' \) -mmin -30)

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
