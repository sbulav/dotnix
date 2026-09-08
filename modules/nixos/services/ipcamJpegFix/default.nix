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
      };
      wantedBy = [ "timers.target" ];
    };

    # Run independently so retained images cannot delay recent photos.
    systemd.timers.ipcam-jpegfix-backlog = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };
    systemd.services.ipcam-jpegfix-backlog = {
      description = "Repair retained camera JPEGs without delaying new photos";
      # Timer-driven oneshots: restarting them on switch would block
      # activation until a full scan finishes. The next timer run picks up
      # the new script anyway.
      restartIfChanged = false;
      environment.BACKLOG_SCAN = "1";
      script = config.systemd.services.ipcam-jpegfix.script;
      serviceConfig =
        (removeAttrs config.systemd.services.ipcam-jpegfix.serviceConfig [ "ExecStart" ])
        // {
          RuntimeDirectory = "ipcam-jpegfix-backlog";
          Nice = 19;
          CPUQuota = "25%";
        };
    };

    services.prometheus.exporters.node.extraFlags = [
      "--collector.textfile.directory=/var/lib/node_exporter/textfile_collector"
    ];
    systemd.tmpfiles.rules = [ "d /var/lib/node_exporter/textfile_collector 0755 root root -" ];

    systemd.services."ipcam-jpegfix" = {
      description = "Convert IP-camera JPEG files with jpegtran to fix proprietary bits";
      restartIfChanged = false;
      script = ''
        set -euo pipefail

        processed=0
        converted=0
        unchanged=0
        repaired_warnings=0
        skipped_empty=0
        skipped_unstable=0
        skipped_vanished=0
        failed=0

        JPEGTRAN=${lib.getExe' pkgs.libjpeg_turbo "jpegtran"}
        SEARCH_DIR=${escapeShellArg cfg.directory}
        MINIMUM_AGE=${escapeShellArg "${toString cfg.minimumAgeMinutes} minutes ago"}
        SCAN_WINDOW=${escapeShellArg "${toString cfg.scanWindowMinutes} minutes ago"}

        now=$(${pkgs.coreutils}/bin/date +%s)
        full_scan=''${BACKLOG_SCAN:-0}
        metric_prefix=ipcam_jpegfix
        age_filter=( -newermt "$SCAN_WINDOW" )
        if [ "$full_scan" -eq 1 ]; then
          metric_prefix=ipcam_jpegfix_backlog
          age_filter=()
        fi

        scratch_dir="''${RUNTIME_DIRECTORY:?RuntimeDirectory must be set}"
        file_list="$(${pkgs.coreutils}/bin/mktemp)"
        scratch=""
        tmpfile=""
        error_file=""

        # Drop per-file temporaries. The scratch copy lives in the tmpfs
        # runtime directory; tmpfile is only ever created next to a JPEG that
        # actually needs replacing.
        discard() {
          if [ -n "$scratch" ]; then
            ${pkgs.coreutils}/bin/rm -f -- "$scratch"
            scratch=""
          fi
          if [ -n "$tmpfile" ]; then
            ${pkgs.coreutils}/bin/rm -f -- "$tmpfile"
            tmpfile=""
          fi
          if [ -n "$error_file" ]; then
            ${pkgs.coreutils}/bin/rm -f -- "$error_file"
            error_file=""
          fi
        }

        publish_metrics() {
          local result=$1 metrics_tmp
          metrics_tmp="$(${pkgs.coreutils}/bin/mktemp /var/lib/node_exporter/textfile_collector/.ipcam-jpegfix.XXXXXX)" \
            && {
              echo "''${metric_prefix}_last_run_timestamp_seconds $now"
              echo "''${metric_prefix}_success $((result == 0))"
              echo "''${metric_prefix}_failed_files $failed"
              echo "''${metric_prefix}_converted_files $converted"
              echo "''${metric_prefix}_skipped_empty_files $skipped_empty"
              echo "''${metric_prefix}_skipped_vanished_files $skipped_vanished"
            } > "$metrics_tmp" \
            && ${pkgs.coreutils}/bin/chmod 0644 "$metrics_tmp" \
            && ${pkgs.coreutils}/bin/mv -f "$metrics_tmp" /var/lib/node_exporter/textfile_collector/"$metric_prefix".prom
        }

        # The trap must never change the script's exit status or leave
        # temporaries behind, so metric publishing is allowed to fail loudly.
        cleanup() {
          result=$?
          if ! publish_metrics "$result"; then
            echo "Warning: failed to publish metrics for $metric_prefix" >&2
          fi
          discard
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
          "''${age_filter[@]}" \
          -print0 > "$file_list"; then
          if [ ! -d "$SEARCH_DIR" ]; then
            echo "JPEG search directory vanished: $SEARCH_DIR" >&2
            exit 1
          fi
          # ipcam-cleanup prunes expired date directories hourly and can race
          # with this scan; find still lists everything it managed to see.
          echo "Warning: enumeration reported errors, continuing with partial list" >&2
        fi

        while IFS= read -r -d "" jpgfile; do
          processed=$((processed + 1))

          # ipcam-cleanup prunes expired date directories hourly; a file it
          # removed after enumeration is not a failure.
          if [ ! -e "$jpgfile" ]; then
            echo "Skipped JPEG removed during scan: $jpgfile"
            skipped_vanished=$((skipped_vanished + 1))
            continue
          fi

          if [ ! -s "$jpgfile" ]; then
            echo "Warning: empty file: $jpgfile"
            skipped_empty=$((skipped_empty + 1))
            continue
          fi

          if ! before="$(${pkgs.coreutils}/bin/stat -c '%d:%i:%s:%y' -- "$jpgfile")"; then
            if [ ! -e "$jpgfile" ]; then
              echo "Skipped JPEG removed during scan: $jpgfile"
              skipped_vanished=$((skipped_vanished + 1))
              continue
            fi
            echo "Failed to stat JPEG before conversion: $jpgfile" >&2
            failed=$((failed + 1))
            continue
          fi

          # Re-encode into tmpfs first. Almost every file comes out identical,
          # so no disk is written unless the image really needs replacing.
          if ! scratch="$(${pkgs.coreutils}/bin/mktemp --tmpdir="$scratch_dir" '.scratch.XXXXXX')" \
            || ! error_file="$(${pkgs.coreutils}/bin/mktemp --tmpdir="$scratch_dir" '.stderr.XXXXXX')"; then
            echo "Failed to create scratch files in $scratch_dir: $jpgfile" >&2
            failed=$((failed + 1))
            discard
            continue
          fi

          if "$JPEGTRAN" -copy none "$jpgfile" > "$scratch" 2> "$error_file"; then
            status=0
          else
            status=$?
          fi

          if ! after="$(${pkgs.coreutils}/bin/stat -c '%d:%i:%s:%y' -- "$jpgfile")" || [ "$before" != "$after" ]; then
            echo "Skipped JPEG that changed during conversion: $jpgfile" >&2
            skipped_unstable=$((skipped_unstable + 1))
            discard
            continue
          fi

          if { [ "$status" -ne 0 ] && [ "$status" -ne 2 ]; } || [ ! -s "$scratch" ]; then
            echo "jpegtran failed with status $status: $jpgfile" >&2
            ${pkgs.coreutils}/bin/head -n 5 "$error_file" >&2 || true
            failed=$((failed + 1))
            discard
            continue
          fi

          if ${pkgs.diffutils}/bin/cmp -s -- "$jpgfile" "$scratch"; then
            unchanged=$((unchanged + 1))
            discard
            continue
          fi

          # Warnings can include malformed metadata or damaged image data.
          # Only accept repaired output when it validates cleanly.
          if ! "$JPEGTRAN" -copy none "$scratch" > /dev/null 2>> "$error_file"; then
            echo "jpegtran produced an invalid replacement: $jpgfile" >&2
            ${pkgs.coreutils}/bin/head -n 5 "$error_file" >&2 || true
            failed=$((failed + 1))
            discard
            continue
          fi

          # Only now write to the camera filesystem: stage next to the
          # original so the final rename stays atomic.
          if ! tmpfile="$(${pkgs.coreutils}/bin/mktemp \
            --tmpdir="$(${pkgs.coreutils}/bin/dirname -- "$jpgfile")" \
            '.ipcam-jpegfix.XXXXXX')"; then
            echo "Failed to create staging file next to JPEG: $jpgfile" >&2
            failed=$((failed + 1))
            discard
            continue
          fi

          if ! ${pkgs.coreutils}/bin/cp -- "$scratch" "$tmpfile" \
            || ! ${pkgs.coreutils}/bin/chmod --reference="$jpgfile" "$tmpfile" \
            || ! ${pkgs.coreutils}/bin/chown --reference="$jpgfile" "$tmpfile" \
            || ! ${pkgs.coreutils}/bin/touch --reference="$jpgfile" "$tmpfile"; then
            echo "Failed to stage replacement JPEG: $jpgfile" >&2
            failed=$((failed + 1))
            discard
            continue
          fi

          if ! ${pkgs.coreutils}/bin/mv -f -- "$tmpfile" "$jpgfile"; then
            echo "Failed to atomically replace JPEG: $jpgfile" >&2
            failed=$((failed + 1))
            discard
            continue
          fi

          tmpfile=""
          discard
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
        echo "Skipped vanished: $skipped_vanished"
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
        # tmpfs scratch space for re-encoded candidates; /tmp is on disk here.
        RuntimeDirectory = "ipcam-jpegfix";
      };
    };
  };
}
