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

        processed=0
        converted=0
        failed=0

        JPEGTRAN=/run/current-system/sw/bin/jpegtran
        SEARCH_DIR="/tank/ipcam/hcam"

        while IFS= read -r -d "" jpgfile; do
          processed=$((processed + 1))

          if [ ! -s "$jpgfile" ]; then
            echo "Warning: empty file: $jpgfile"
            failed=$((failed + 1))
            continue
          fi

          # safe tmp
          tmpfile="$(mktemp -p "$(dirname "$jpgfile")")"
          chmod 660 "$tmpfile" || true
          chown nobody:nogroup "$tmpfile" || true

          # NEVER allow jpegtran exit code to trigger set -e
          "$JPEGTRAN" -copy none "$jpgfile" > "$tmpfile" 2>/dev/null || true
          status=$?

          if [ $status -eq 0 ] || [ $status -eq 2 ]; then

            if /run/current-system/sw/bin/cmp -s "$jpgfile" "$tmpfile"; then
              rm -f "$tmpfile"
              echo "Unchanged: $jpgfile"
            else
              touch -r "$jpgfile" "$tmpfile" || true
              if cat "$tmpfile" > "$jpgfile"; then
                touch -r "$tmpfile" "$jpgfile" || true
                chmod 660 "$jpgfile" || true
                chown nobody:nogroup "$jpgfile" || true
                echo "Converted: $jpgfile"
                converted=$((converted + 1))
              else
                echo "Error overwriting $jpgfile" >&2
                failed=$((failed + 1))
              fi
              rm -f "$tmpfile"
            fi

          else
            echo "jpegtran error $status: $jpgfile" >&2
            rm -f "$tmpfile"
            failed=$((failed + 1))
          fi

        done < <(find "$SEARCH_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) -mmin -30 -print0 || true)

        echo "Processed: $processed"
        echo "Converted: $converted"
        echo "Failed: $failed"

      '';
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
    };
  };
}
