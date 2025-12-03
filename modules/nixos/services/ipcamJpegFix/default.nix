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

        JPEGTRAN=/nix/store/54rrraasls3cass3hzry95wb8hm75vqq-libjpeg-turbo-3.1.2-bin/bin/jpegtran
        SEARCH_DIR="/tank/ipcam/hcam"

        while IFS= read -r -d "" jpgfile; do
          processed=$((processed + 1))

          if [ ! -s "$jpgfile" ]; then
            printf 'Warning: Skipping empty file: %s\n' "$jpgfile"
            failed=$((failed + 1))
            continue
          fi

          tmpfile="$(mktemp "$(dirname "$jpgfile")/$(basename "$jpgfile").tmp.XXXXXX")"
          chown nobody:nogroup "$tmpfile" 2>/dev/null || true

          # printf '%s -copy none %s > %s\n' "$JPEGTRAN" "$jpgfile" "$tmpfile"

          # Run jpegtran and capture exit status
          "$JPEGTRAN" -copy none "$jpgfile" > "$tmpfile" 2>/dev/null
          status=$?

          # jpegtran exit codes:
          #   0 = success
          #   1 = fatal error
          #   2 = warning but output is valid
          if [ $status -eq 0 ] || [ $status -eq 2 ]; then

            if /run/current-system/sw/bin/cmp -s "$jpgfile" "$tmpfile"; then
              rm -f -- "$tmpfile"
              # printf 'Unchanged: %s\n' "$jpgfile"
            else
              touch -r "$jpgfile" "$tmpfile" || true

              if cat "$tmpfile" > "$jpgfile"; then
                touch -r "$tmpfile" "$jpgfile" || true
                chmod 660 "$jpgfile" 2>/dev/null || true
                chown nobody:nogroup "$jpgfile" 2>/dev/null || true
                converted=$((converted + 1))
                # printf 'Converted: %s\n' "$jpgfile"
              else
                printf 'Error: Failed to overwrite original: %s\n' "$jpgfile" >&2
                failed=$((failed + 1))
              fi

              rm -f -- "$tmpfile"
            fi

          else
            printf 'Error: jpegtran failed (%d) for %s\n' "$status" "$jpgfile" >&2
            rm -f -- "$tmpfile"
            failed=$((failed + 1))
          fi

        done < <(find "$SEARCH_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) -mmin -30 -print0 || true)

        printf '\nJPEG Fix Summary:\n'
        printf '  Processed: %d files\n' "$processed"
        printf '  Converted: %d files\n' "$converted"
        printf '  Failed:    %d files\n' "$failed"
      '';
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
    };
  };
}
