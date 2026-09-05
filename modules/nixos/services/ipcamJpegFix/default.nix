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
    directory = mkOpt str "/tank/ipcam/hcam" "Directory containing IP-camera JPEG files.";
    interval = mkOpt str "10min" "How often to scan for new JPEG files.";
    minimumAgeMinutes = mkOpt ints.positive 2 "Minimum file age before a JPEG may be processed.";
    scanWindowMinutes = mkOpt ints.positive 30 "Maximum file age included in each scan.";
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.scanWindowMinutes > cfg.minimumAgeMinutes;
        message = "ipcamJpegFix.scanWindowMinutes must be greater than minimumAgeMinutes";
      }
    ];

    # Install libjpeg which provides jpegtran
    environment.systemPackages = with pkgs; [
      libjpeg_turbo
    ];

    systemd.timers."ipcam-jpegfix" = {
      description = "Fix IP-camera JPEG files every 10 minutes";
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = cfg.interval;
        Persistent = true;
      };
      wantedBy = [ "timers.target" ];
    };

    systemd.services."ipcam-jpegfix" = {
      description = "Convert IP-camera JPEG files with jpegtran to fix proprietary bits";
      script = ''
        set -euo pipefail

        processed=0
        converted=0
        unchanged=0
        repaired_warnings=0
        skipped_empty=0
        skipped_unstable=0
        failed=0

        JPEGTRAN=${lib.getExe' pkgs.libjpeg_turbo "jpegtran"}
        SEARCH_DIR=${escapeShellArg cfg.directory}
        MINIMUM_AGE=${escapeShellArg "${toString cfg.minimumAgeMinutes} minutes ago"}
        SCAN_WINDOW=${escapeShellArg "${toString cfg.scanWindowMinutes} minutes ago"}

        file_list="$(${pkgs.coreutils}/bin/mktemp)"
        tmpfile=""
        error_file=""

        cleanup() {
          if [ -n "$tmpfile" ]; then
            ${pkgs.coreutils}/bin/rm -f -- "$tmpfile"
          fi
          if [ -n "$error_file" ]; then
            ${pkgs.coreutils}/bin/rm -f -- "$error_file"
          fi
          ${pkgs.coreutils}/bin/rm -f -- "$file_list"
        }
        trap cleanup EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM

        if [ ! -d "$SEARCH_DIR" ]; then
          echo "JPEG search directory does not exist: $SEARCH_DIR" >&2
          exit 1
        fi

        if ! ${pkgs.findutils}/bin/find "$SEARCH_DIR" \
          -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) \
          ! -newermt "$MINIMUM_AGE" \
          -newermt "$SCAN_WINDOW" \
          -print0 > "$file_list"; then
          echo "Failed to enumerate JPEG files in $SEARCH_DIR" >&2
          exit 1
        fi

        while IFS= read -r -d "" jpgfile; do
          processed=$((processed + 1))

          if [ ! -s "$jpgfile" ]; then
            echo "Warning: empty file: $jpgfile"
            skipped_empty=$((skipped_empty + 1))
            continue
          fi

          if ! before="$(${pkgs.coreutils}/bin/stat -c '%d:%i:%s:%y' -- "$jpgfile")"; then
            echo "Failed to stat JPEG before conversion: $jpgfile" >&2
            failed=$((failed + 1))
            continue
          fi

          tmpfile="$(${pkgs.coreutils}/bin/mktemp \
            --tmpdir="$(${pkgs.coreutils}/bin/dirname -- "$jpgfile")" \
            '.ipcam-jpegfix.XXXXXX')"
          error_file="$(${pkgs.coreutils}/bin/mktemp)"

          if "$JPEGTRAN" -copy none "$jpgfile" > "$tmpfile" 2> "$error_file"; then
            status=0
          else
            status=$?
          fi

          if ! after="$(${pkgs.coreutils}/bin/stat -c '%d:%i:%s:%y' -- "$jpgfile")" || [ "$before" != "$after" ]; then
            echo "Skipped JPEG that changed during conversion: $jpgfile" >&2
            skipped_unstable=$((skipped_unstable + 1))
            ${pkgs.coreutils}/bin/rm -f -- "$tmpfile" "$error_file"
            tmpfile=""
            error_file=""
            continue
          fi

          if { [ "$status" -ne 0 ] && [ "$status" -ne 2 ]; } || [ ! -s "$tmpfile" ]; then
            echo "jpegtran failed with status $status: $jpgfile" >&2
            ${pkgs.coreutils}/bin/head -n 5 "$error_file" >&2 || true
            failed=$((failed + 1))
            ${pkgs.coreutils}/bin/rm -f -- "$tmpfile" "$error_file"
            tmpfile=""
            error_file=""
            continue
          fi

          # Status 2 is the expected warning for the camera's proprietary DHAV
          # metadata. Only accept it when the stripped output validates cleanly.
          if ! "$JPEGTRAN" -copy none "$tmpfile" > /dev/null 2>> "$error_file"; then
            echo "jpegtran produced an invalid replacement: $jpgfile" >&2
            ${pkgs.coreutils}/bin/head -n 5 "$error_file" >&2 || true
            failed=$((failed + 1))
            ${pkgs.coreutils}/bin/rm -f -- "$tmpfile" "$error_file"
            tmpfile=""
            error_file=""
            continue
          fi

          if ${pkgs.diffutils}/bin/cmp -s -- "$jpgfile" "$tmpfile"; then
            unchanged=$((unchanged + 1))
            ${pkgs.coreutils}/bin/rm -f -- "$tmpfile" "$error_file"
            tmpfile=""
            error_file=""
            continue
          fi

          if ! ${pkgs.coreutils}/bin/chmod --reference="$jpgfile" "$tmpfile" \
            || ! ${pkgs.coreutils}/bin/chown --reference="$jpgfile" "$tmpfile" \
            || ! ${pkgs.coreutils}/bin/touch --reference="$jpgfile" "$tmpfile"; then
            echo "Failed to preserve JPEG metadata: $jpgfile" >&2
            failed=$((failed + 1))
            ${pkgs.coreutils}/bin/rm -f -- "$tmpfile" "$error_file"
            tmpfile=""
            error_file=""
            continue
          fi

          if ! ${pkgs.coreutils}/bin/mv -f -- "$tmpfile" "$jpgfile"; then
            echo "Failed to atomically replace JPEG: $jpgfile" >&2
            failed=$((failed + 1))
            ${pkgs.coreutils}/bin/rm -f -- "$tmpfile" "$error_file"
            tmpfile=""
            error_file=""
            continue
          fi

          tmpfile=""
          ${pkgs.coreutils}/bin/rm -f -- "$error_file"
          error_file=""
          converted=$((converted + 1))
          if [ "$status" -eq 2 ]; then
            repaired_warnings=$((repaired_warnings + 1))
          fi
        done < "$file_list"

        echo "Processed: $processed"
        echo "Converted: $converted"
        echo "Unchanged: $unchanged"
        echo "Repaired warnings: $repaired_warnings"
        echo "Skipped empty: $skipped_empty"
        echo "Skipped unstable: $skipped_unstable"
        echo "Failed: $failed"

        if [ "$failed" -ne 0 ]; then
          exit 1
        fi
      '';
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        UMask = "0007";
        Nice = 10;
        IOSchedulingClass = "idle";
        PrivateTmp = true;
        ProtectHome = true;
      };
    };
  };
}
