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
  cfg = config.${namespace}.services.zanoza-external-monitoring;
  textfileDirectory = "/var/lib/node_exporter/textfile_collector";
  hostName = config.networking.hostName;

  # Three monitors share one delivery path and one alert state machine but
  # keep separate state, metrics and schedules, so an unavailable backup disk
  # never blocks the reachability probes (or their alerts) and vice versa.
  monitors = {
    external = {
      unit = "zanoza-external-monitor";
      friendlyName = "External zanoza monitor";
      metricPrefix = "zanoza_external_monitor";
      metricsFile = "zanoza_external.prom";
      recoveryText = "All reachability, DNS and HTTP checks pass.";
      threshold = cfg.failureThreshold;
    };
    backup = {
      unit = "zanoza-backup-monitor";
      friendlyName = "Zanoza backup freshness";
      metricPrefix = "zanoza_backup_monitor";
      metricsFile = "zanoza_backup.prom";
      recoveryText = "The repository is reachable and every backup job has a fresh snapshot.";
      threshold = cfg.failureThreshold;
    };
    verify = {
      unit = "zanoza-backup-verify";
      friendlyName = "Zanoza backup verification";
      metricPrefix = "zanoza_backup_verify";
      metricsFile = "zanoza_backup_verify.prom";
      recoveryText = "Repository check and restore verification pass again.";
      # Weekly: one failed run is worth an alert.
      threshold = 1;
    };
  };

  deliverScript = lib.custom.notifications.mkDeliverScript pkgs {
    inherit hostName;
    telegram = {
      inherit (cfg.telegram) enable chatId proxyUrl;
    };
    email = {
      inherit (cfg.email) enable recipient;
      fromName = "${hostName} external monitor";
    };
  };
  deliver = "${deliverScript}/bin/notify-deliver";
  evaluate = "${pkgs.custom.monitor-state-machine}/bin/monitor-evaluate";

  # Shell prologue/epilogue shared by the monitor scripts: results go to a TSV
  # consumed by monitor-evaluate, probe gauges go to a temp file that is
  # published atomically after the state machine appended its own gauges.
  prologue = monitor: ''
    metrics_tmp=$(mktemp ${escapeShellArg textfileDirectory}/.${monitor.metricsFile}.XXXXXX)
    results_tmp=$(mktemp)
    stderr_tmp=$(mktemp)
    scratch_dirs=()
    # shellcheck disable=SC2329  # invoked through the EXIT trap
    cleanup() {
      rm -f "$metrics_tmp" "$results_tmp" "$stderr_tmp"
      [ "''${#scratch_dirs[@]}" -eq 0 ] || rm -rf "''${scratch_dirs[@]}"
    }
    # systemd stops a unit with SIGTERM (TimeoutStartSec); bash skips the EXIT
    # trap on an unhandled signal, so route the signals through exit.
    trap cleanup EXIT
    trap 'exit 143' TERM INT
    now=$(date +%s)

    record_result() {
      # record_result <name> <1|0> <detail>; detail is one TSV field
      local detail=$3
      detail=''${detail//$'\t'/ }
      detail=''${detail//$'\n'/ }
      printf '%s\t%s\t%s\n' "$1" "$2" "$detail" >>"$results_tmp"
    }
  '';
  epilogue = monitor: ''
    rc=0
    MONITOR_STATE_DIR=$STATE_DIRECTORY \
    MONITOR_RESULTS="$results_tmp" \
    MONITOR_DELIVER=${deliver} \
    MONITOR_NAME=${escapeShellArg monitor.friendlyName} \
    MONITOR_HOST=${escapeShellArg hostName} \
    MONITOR_FAILURE_THRESHOLD=${toString monitor.threshold} \
    MONITOR_MIN_INTERVAL=${toString cfg.notificationMinIntervalSeconds} \
    MONITOR_NOW="$now" \
    MONITOR_RECOVERY_TEXT=${escapeShellArg monitor.recoveryText} \
    MONITOR_HINT=${escapeShellArg "Inspect with: journalctl -u ${monitor.unit}.service"} \
    MONITOR_METRIC_PREFIX=${monitor.metricPrefix} \
    MONITOR_METRICS_OUT="$metrics_tmp" \
      ${evaluate} || rc=$?

    chmod 0644 "$metrics_tmp"
    mv -f "$metrics_tmp" ${escapeShellArg "${textfileDirectory}/${monitor.metricsFile}"}
    exit "$rc"
  '';

  externalScript = pkgs.writeShellApplication {
    name = monitors.external.unit;
    runtimeInputs = with pkgs; [
      bind.dnsutils
      coreutils
      curl
      gnugrep
      netcat-openbsd
    ];
    text = ''
      ${prologue monitors.external}

      cat >"$metrics_tmp" <<'EOF'
      # HELP zanoza_external_probe_success Whether an external zanoza probe succeeded.
      # TYPE zanoza_external_probe_success gauge
      EOF

      probe() {
        # probe <name> <kind> <1|0> <detail>
        printf 'zanoza_external_probe_success{probe="%s",kind="%s"} %s\n' "$1" "$2" "$3" >>"$metrics_tmp"
        record_result "$1" "$3" "$4"
      }

      probe_http() {
        if curl --fail --location --silent --show-error \
          --output /dev/null \
          --connect-timeout ${toString cfg.connectTimeoutSeconds} \
          --max-time ${toString cfg.probeTimeoutSeconds} \
          "$2"; then
          probe "$1" http 1 ok
        else
          probe "$1" http 0 "HTTP request failed: $2"
        fi
      }

      probe_tcp() {
        if nc -z -w ${toString cfg.connectTimeoutSeconds} "$2" "$3"; then
          probe "$1" tcp 1 ok
        else
          probe "$1" tcp 0 "TCP connection failed: $2:$3"
        fi
      }

      probe_dns() {
        local answer
        answer=$(dig +short \
          +time=${toString cfg.connectTimeoutSeconds} \
          +tries=1 \
          @${escapeShellArg cfg.dns.server} \
          ${escapeShellArg cfg.dns.name} A 2>/dev/null \
          | grep -E '^[0-9]+(\.[0-9]+){3}$' \
          | head -n 1 \
          || true)

        if [ -z "$answer" ]; then
          probe dns_resolution dns 0 "${cfg.dns.server} did not resolve ${cfg.dns.name}"
        ${optionalString (cfg.dns.expectedAddress != "") ''
          elif [ "$answer" != ${escapeShellArg cfg.dns.expectedAddress} ]; then
            probe dns_resolution dns 0 "${cfg.dns.name} resolved to $answer, expected ${cfg.dns.expectedAddress}"
        ''}
        else
          probe dns_resolution dns 1 ok
        fi
      }

      ${concatMapStringsSep "\n" (target: ''
        probe_tcp ${escapeShellArg target.name} ${escapeShellArg target.address} ${toString target.port}
      '') cfg.tcpTargets}
      probe_dns
      ${concatMapStringsSep "\n" (target: ''
        probe_http ${escapeShellArg target.name} ${escapeShellArg target.url}
      '') cfg.httpTargets}

      ${epilogue monitors.external}
    '';
  };

  # restic invocation shared by the freshness and verification monitors. The
  # repository password is the only secret needed; `--no-cache` keeps the
  # read-only queries from writing anywhere but the repository lock dir.
  resticCommand = concatStringsSep " " [
    "restic"
    "--repo ${escapeShellArg cfg.backup.repositoryPath}"
    "--password-file ${escapeShellArg config.sops.secrets.${cfg.backup.passwordSecret}.path}"
    "--no-cache"
    "--quiet"
  ];

  jobSelector =
    job:
    concatStringsSep " " (
      map (tag: "--tag ${escapeShellArg tag}") job.matchTags
      ++ map (path: "--path ${escapeShellArg path}") job.matchPaths
    );

  jobStaleAfter =
    job: if job.staleAfterSeconds != null then job.staleAfterSeconds else cfg.backup.staleAfterSeconds;

  # Accessing an autofs path triggers the mount; bound the wait so a dead USB
  # disk turns into a failed check instead of a hung unit.
  # The gauge carries the monitor's prefix: the same series in two textfiles
  # would make node_exporter reject the duplicate.
  repositoryProbe = monitor: checkName: ''
    repository_ok=0
    if timeout -k 10 ${toString cfg.backup.mountTimeoutSeconds} test -f ${escapeShellArg "${cfg.backup.repositoryPath}/config"}; then
      repository_ok=1
      record_result ${checkName} 1 ok
    else
      record_result ${checkName} 0 ${escapeShellArg "restic repository unavailable at ${cfg.backup.repositoryPath} (backup disk not mounted?)"}
    fi
    printf '${monitor.metricPrefix}_repository_available %s\n' "$repository_ok" >>"$metrics_tmp"
  '';

  backupScript = pkgs.writeShellApplication {
    name = monitors.backup.unit;
    runtimeInputs = with pkgs; [
      coreutils
      jq
      restic
    ];
    text = ''
      ${prologue monitors.backup}

      cat >"$metrics_tmp" <<'EOF'
      # HELP zanoza_backup_monitor_repository_available Whether the restic repository on the backup disk is readable.
      # TYPE zanoza_backup_monitor_repository_available gauge
      # HELP zanoza_backup_job_snapshot_age_seconds Age of the newest snapshot of a backup job (-1 when unknown).
      # TYPE zanoza_backup_job_snapshot_age_seconds gauge
      # HELP zanoza_backup_job_fresh Whether the newest snapshot of a backup job is younger than its limit.
      # TYPE zanoza_backup_job_fresh gauge
      # HELP zanoza_backup_job_snapshot_timestamp_seconds Unix time of the newest snapshot of a backup job.
      # TYPE zanoza_backup_job_snapshot_timestamp_seconds gauge
      EOF

      job_metrics() {
        # job_metrics <job> <age> <fresh> <timestamp>
        {
          printf 'zanoza_backup_job_snapshot_age_seconds{job="%s"} %s\n' "$1" "$2"
          printf 'zanoza_backup_job_fresh{job="%s"} %s\n' "$1" "$3"
          printf 'zanoza_backup_job_snapshot_timestamp_seconds{job="%s"} %s\n' "$1" "$4"
        } >>"$metrics_tmp"
      }

      check_job() {
        # check_job <job> <stale-after> <expected-paths...> -- <restic selector args...>
        local job="$1" stale_after="$2" expected=() snapshots snapshot snapshot_id snapshot_epoch age path
        local candidate_time candidate_id candidate_epoch
        shift 2
        while [ "$#" -gt 0 ] && [ "$1" != -- ]; do
          expected+=("$1")
          shift
        done
        shift

        # stderr is kept apart: a restic warning on stdout would corrupt the
        # JSON and abort the run with the previous metrics still published.
        if ! snapshots=$(timeout -k 10 ${toString cfg.backup.queryTimeoutSeconds} \
          ${resticCommand} snapshots --no-lock --json --latest 1 "$@" 2>"$stderr_tmp"); then
          job_metrics "$job" -1 0 0
          record_result "backup_$job" 0 "restic snapshots failed: $(tail -n 1 "$stderr_tmp")"
          return
        fi

        # A snapshot only exists when the backup completed; its own timestamp
        # is the freshness signal, not a file mtime or a unit exit code.
        # `--latest 1` still returns one snapshot per host/paths group, so pick
        # the newest by epoch (string order would break across UTC offsets).
        snapshot_epoch=0 snapshot_id=""
        while IFS=$'\t' read -r candidate_time candidate_id; do
          candidate_epoch=$(date -d "$candidate_time" +%s 2>/dev/null) || continue
          if [ "$candidate_epoch" -gt "$snapshot_epoch" ]; then
            snapshot_epoch=$candidate_epoch
            snapshot_id=$candidate_id
          fi
        done < <(printf '%s' "$snapshots" | jq -r '.[]? | [.time, .id] | @tsv')

        if [ -z "$snapshot_id" ]; then
          job_metrics "$job" -1 0 0
          record_result "backup_$job" 0 "no snapshot matches selector: $*"
          return
        fi
        snapshot=$(printf '%s' "$snapshots" | jq -c --arg id "$snapshot_id" '.[] | select(.id == $id)')
        age=$((now - snapshot_epoch))

        for path in "''${expected[@]}"; do
          if ! printf '%s' "$snapshot" | jq -e --arg p "$path" '.paths | index($p) != null' >/dev/null; then
            job_metrics "$job" "$age" 0 "$snapshot_epoch"
            record_result "backup_$job" 0 \
              "newest snapshot $(printf '%s' "$snapshot" | jq -r '.short_id') lacks path $path"
            return
          fi
        done

        if [ "$age" -le "$stale_after" ]; then
          job_metrics "$job" "$age" 1 "$snapshot_epoch"
          record_result "backup_$job" 1 ok
        else
          job_metrics "$job" "$age" 0 "$snapshot_epoch"
          record_result "backup_$job" 0 \
            "newest snapshot is $((age / 3600))h old (limit $((stale_after / 3600))h)"
        fi
      }

      ${repositoryProbe monitors.backup "backup_repository"}

      if [ "$repository_ok" = 1 ]; then
        ${concatMapStringsSep "\n" (job: ''
          check_job ${escapeShellArg job.name} ${toString (jobStaleAfter job)} \
            ${concatMapStringsSep " " escapeShellArg job.expectedPaths} -- ${jobSelector job}
        '') cfg.backup.jobs}
      else
        # One root cause, one alert: the jobs are unknown, not failed.
        ${concatMapStringsSep "\n" (job: ''
          job_metrics ${escapeShellArg job.name} -1 0 0
        '') cfg.backup.jobs}
      fi

      ${epilogue monitors.backup}
    '';
  };

  verifyJobs = filter (job: job.verify.include != "") cfg.backup.jobs;

  verifyScript = pkgs.writeShellApplication {
    name = monitors.verify.unit;
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      restic
    ];
    text = ''
      ${prologue monitors.verify}
      restore_root=$STATE_DIRECTORY/restore-test
      scratch_dirs+=("$restore_root")

      cat >"$metrics_tmp" <<'EOF'
      # HELP zanoza_backup_verify_repository_available Whether the restic repository on the backup disk is readable.
      # TYPE zanoza_backup_verify_repository_available gauge
      # HELP zanoza_backup_verify_success Result of a verification step (repository check or per-job restore).
      # TYPE zanoza_backup_verify_success gauge
      # HELP zanoza_backup_verify_restored_bytes Bytes restored by the per-job restore verification.
      # TYPE zanoza_backup_verify_restored_bytes gauge
      # HELP zanoza_backup_verify_duration_seconds Duration of a verification step.
      # TYPE zanoza_backup_verify_duration_seconds gauge
      EOF

      step_metrics() {
        # step_metrics <step> <job> <success> <duration>
        {
          printf 'zanoza_backup_verify_success{step="%s",job="%s"} %s\n' "$1" "$2" "$3"
          printf 'zanoza_backup_verify_duration_seconds{step="%s",job="%s"} %s\n' "$1" "$2" "$4"
        } >>"$metrics_tmp"
      }

      run_check() {
        local started
        started=$(date +%s)
        # Integrity: structure plus a random sample of pack data. Needs the
        # exclusive repository lock, hence the schedule outside zanoza's
        # backup window.
        if ${resticCommand} check --read-data-subset=${escapeShellArg cfg.backup.verify.readDataSubset} >"$stderr_tmp" 2>&1; then
          step_metrics check "" 1 $(($(date +%s) - started))
          record_result repository_check 1 ok
        else
          step_metrics check "" 0 $(($(date +%s) - started))
          record_result repository_check 0 "restic check failed: $(tail -n 1 "$stderr_tmp")"
        fi
      }

      run_restore() {
        # run_restore <job> <include> <expect-file> -- <selector args...>
        local job="$1" include="$2" expect="$3" target started files bytes
        shift 3
        shift
        target=$restore_root/$job
        rm -rf "$target"
        mkdir -p "$target"
        started=$(date +%s)
        # Recoverability: a real restore of a small, meaningful subset into a
        # scratch directory, then check that files actually came back.
        if ! ${resticCommand} restore latest "$@" --target "$target" --include "$include" >"$stderr_tmp" 2>&1; then
          step_metrics restore "$job" 0 $(($(date +%s) - started))
          record_result "restore_$job" 0 "restic restore failed: $(tail -n 1 "$stderr_tmp")"
          rm -rf "$target"
          return
        fi
        files=$(find "$target" -type f | wc -l)
        bytes=$(du -sb "$target" | cut -f1)
        printf 'zanoza_backup_verify_restored_bytes{job="%s"} %s\n' "$job" "$bytes" >>"$metrics_tmp"
        if [ "$files" -eq 0 ]; then
          step_metrics restore "$job" 0 $(($(date +%s) - started))
          record_result "restore_$job" 0 "restore of $include produced no files"
        elif [ -n "$expect" ] && [ ! -f "$target$expect" ]; then
          step_metrics restore "$job" 0 $(($(date +%s) - started))
          record_result "restore_$job" 0 "restored tree lacks $expect"
        else
          step_metrics restore "$job" 1 $(($(date +%s) - started))
          record_result "restore_$job" 1 ok
        fi
        rm -rf "$target"
      }

      ${repositoryProbe monitors.verify "verify_repository"}

      if [ "$repository_ok" = 1 ]; then
        run_check
        ${concatMapStringsSep "\n" (job: ''
          run_restore ${escapeShellArg job.name} ${escapeShellArg job.verify.include} \
            ${escapeShellArg job.verify.expectFile} -- ${jobSelector job}
        '') verifyJobs}
      fi

      ${epilogue monitors.verify}
    '';
  };

  # A monitor that dies before publishing (bug, killed by TimeoutStartSec)
  # would otherwise leave its last metrics in place and nobody the wiser.
  mkMonitorFailureService = monitor: {
    description = "Notify that ${monitor.unit} failed";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "10min";
    }
    // telegramEnv;
    path = [
      pkgs.coreutils
      pkgs.systemd
    ];
    script = ''
      message_file=$(mktemp)
      trap 'rm -f "$message_file"' EXIT
      trap 'exit 143' TERM INT
      unit=${monitor.unit}.service
      show() { systemctl show -p "$1" --value "$unit" 2>/dev/null || echo unknown; }
      {
        printf '%s\n' "🔥 ${hostName} | ${monitor.friendlyName}: monitor unit failed"
        printf 'Unit: %s\nResult: %s (main process %s, status %s)\n\nLast journal lines:\n' \
          "$unit" "$(show Result)" "$(show ExecMainCode)" "$(show ExecMainStatus)"
        journalctl -u "$unit" -n 15 -o cat --no-pager || true
      } >"$message_file"
      ${deliver} "$message_file" "[${hostName}] ${monitor.unit} failed" high
    '';
  };

  notificationTestScript = emailOnly: ''
    message_file=$(mktemp)
    trap 'rm -f "$message_file"' EXIT
    printf '%s\n' \
      "🧪 ${hostName} | External zanoza monitor" \
      "Notification test (${
        if emailOnly then "forced email fallback" else "Telegram with automatic email fallback"
      })." \
      >"$message_file"
    ${optionalString emailOnly "FORCE_EMAIL_ONLY=true "}${deliver} \
      "$message_file" \
      "[${hostName}] external monitor notification test" \
      low
  '';

  hardening = {
    Type = "oneshot";
    UMask = "0022";
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectHome = true;
    ProtectSystem = "strict";
    ReadWritePaths = [ textfileDirectory ];
  };
  # restic check/restore write lock files into the repository, and the
  # repository lives on an autofs mount that must not be pinned by the unit's
  # mount namespace: "full" keeps /usr, /boot and /etc read-only but leaves
  # /mnt writable, and the bounded `test -f` decides availability at runtime.
  resticHardening = hardening // {
    ProtectSystem = "full";
  };
  telegramEnv = optionalAttrs cfg.telegram.enable {
    # Leading dash: a missing token file must not stop the email fallback.
    EnvironmentFile = "-${config.sops.secrets."telegram-notifications-bot-token".path}";
  };
in
{
  options.${namespace}.services.zanoza-external-monitoring = with types; {
    enable = mkBoolOpt false "Monitor critical zanoza endpoints and backups independently from beez";

    tcpTargets = mkOpt (listOf (submodule {
      options = {
        name = mkOption {
          type = str;
          description = "Stable Prometheus label for the TCP probe";
        };
        address = mkOption {
          type = str;
          description = "Address to connect to";
        };
        port = mkOption {
          type = port;
          description = "TCP port to connect to";
        };
      };
    })) [ ] "TCP endpoints used to detect host reachability";

    httpTargets = mkOpt (listOf (submodule {
      options = {
        name = mkOption {
          type = str;
          description = "Stable Prometheus label for the HTTP probe";
        };
        url = mkOption {
          type = str;
          description = "HTTPS URL to request";
        };
      };
    })) [ ] "Reverse proxy and user-facing endpoints to probe";

    dns = {
      server = mkOpt str "172.16.64.104" "AdGuard DNS server reached through zanoza";
      name = mkOpt str "home.sbulav.ru" "Name to resolve through zanoza DNS";
      expectedAddress =
        mkOpt str "192.168.89.207"
          "Expected A record, or an empty string to accept any answer";
    };

    backup = {
      repositoryPath = mkOpt path "/mnt/ext/backup_zanoza" "Restic repository stored on beez";
      passwordSecret =
        mkOpt str "backups/restic_odroid"
          "sops secret (in this host's default sops file) holding the repository password";
      staleAfterSeconds = mkOpt int (36 * 60 * 60) "Default maximum age of a job's newest snapshot";
      checkInterval = mkOpt str "30m" "systemd interval between freshness checks";
      mountTimeoutSeconds =
        mkOpt int 90
          "How long to wait for the autofs backup disk before declaring it unavailable";
      queryTimeoutSeconds = mkOpt int 180 "Timeout for one restic snapshots query";

      jobs = mkOpt (listOf (submodule {
        options = {
          name = mkOption {
            type = str;
            description = "Stable job identity, used as the Prometheus `job` label and in alerts";
          };
          matchTags = mkOption {
            type = listOf str;
            default = [ ];
            description = "restic --tag selectors identifying this job's snapshots (ANDed with matchPaths)";
          };
          matchPaths = mkOption {
            type = listOf str;
            default = [ ];
            description = "restic --path selectors identifying this job's snapshots (ANDed with matchTags)";
          };
          expectedPaths = mkOption {
            type = listOf str;
            default = [ ];
            description = "Paths the newest snapshot must contain to count as a complete backup";
          };
          staleAfterSeconds = mkOption {
            type = nullOr int;
            default = null;
            description = "Per-job freshness limit; null uses backup.staleAfterSeconds";
          };
          verify = {
            include = mkOption {
              type = str;
              default = "";
              description = "Path (restic --include pattern) restored weekly into a scratch directory; empty disables restore verification for the job";
            };
            expectFile = mkOption {
              type = str;
              default = "";
              description = "Absolute path (as stored in the snapshot) that must exist after the verification restore";
            };
          };
        };
      })) [ ] "Backup jobs whose snapshots are tracked independently";

      verify = {
        enable = mkBoolOpt true "Run a weekly repository check and restore verification";
        onCalendar =
          mkOpt str "Sun *-*-* 08:00:00"
            "When to verify; keep it outside zanoza's backup/prune window (01:05-06:35), restic check needs the exclusive lock";
        readDataSubset = mkOpt str "5%" "restic check --read-data-subset argument";
      };
    };

    probeInterval = mkOpt str "2m" "systemd interval between probe batches";
    connectTimeoutSeconds = mkOpt int 5 "Connection timeout for individual probes";
    probeTimeoutSeconds = mkOpt int 15 "Overall timeout for individual probes";
    failureThreshold = mkOpt int 2 "Consecutive failed batches required before alerting";
    notificationMinIntervalSeconds = mkOpt int 900 "Minimum interval between notification attempts";

    telegram = {
      enable = mkBoolOpt true "Try Telegram before the email fallback";
      chatId = mkOpt str "681806836" "Telegram chat ID for alerts";
      proxyUrl = mkOpt str "" "Optional curl proxy URL for Telegram delivery";
    };

    email = {
      enable = mkBoolOpt true "Use msmtp when Telegram delivery fails";
      recipient = mkOpt str "bulavintsev.sergey@gmail.com" "Fallback notification recipient";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.failureThreshold > 0;
        message = "custom.services.zanoza-external-monitoring.failureThreshold must be positive";
      }
      {
        assertion = cfg.notificationMinIntervalSeconds >= 0;
        message = "custom.services.zanoza-external-monitoring.notificationMinIntervalSeconds cannot be negative";
      }
      {
        assertion = all (target: builtins.match "^[a-zA-Z_][a-zA-Z0-9_]*$" target.name != null) (
          cfg.tcpTargets ++ cfg.httpTargets ++ cfg.backup.jobs
        );
        message = "zanoza external monitoring target and backup job names must be valid Prometheus label identifiers";
      }
      {
        assertion = all (job: job.matchTags != [ ] || job.matchPaths != [ ]) cfg.backup.jobs;
        message = "every zanoza external monitoring backup job needs matchTags or matchPaths";
      }
      {
        assertion = cfg.telegram.enable || cfg.email.enable;
        message = "zanoza external monitoring needs at least one notification channel";
      }
      {
        assertion = !cfg.email.enable || config.${namespace}.containers.msmtp.enable;
        message = "zanoza external monitoring email fallback requires custom.containers.msmtp.enable";
      }
    ];

    sops.secrets = {
      "telegram-notifications-bot-token" = mkIf cfg.telegram.enable {
        mode = mkDefault "0400";
        owner = mkDefault "root";
        group = mkDefault "root";
      };
      ${cfg.backup.passwordSecret} = mkIf (cfg.backup.jobs != [ ]) {
        mode = mkDefault "0400";
        owner = mkDefault "root";
        group = mkDefault "root";
      };
    };

    services.prometheus.exporters.node = {
      enable = mkDefault true;
      extraFlags = [ "--collector.textfile.directory=${textfileDirectory}" ];
    };

    systemd.tmpfiles.rules = [
      "d ${textfileDirectory} 0755 root root -"
    ];

    systemd.timers = {
      ${monitors.external.unit} = {
        description = "Run external zanoza health probes";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "3m";
          OnUnitActiveSec = cfg.probeInterval;
          RandomizedDelaySec = "15s";
          Persistent = true;
        };
      };
      ${monitors.backup.unit} = mkIf (cfg.backup.jobs != [ ]) {
        description = "Check zanoza backup freshness per job";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "5m";
          OnUnitActiveSec = cfg.backup.checkInterval;
          RandomizedDelaySec = "2m";
          Persistent = true;
        };
      };
      ${monitors.verify.unit} = mkIf (cfg.backup.verify.enable && cfg.backup.jobs != [ ]) {
        description = "Verify the zanoza restic repository and restore a sample";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.backup.verify.onCalendar;
          RandomizedDelaySec = "10m";
          Persistent = true;
        };
      };
    };

    systemd.services = {
      # Network/host probes: no dependency on the backup disk at all.
      ${monitors.external.unit} = {
        description = "Monitor zanoza independently from beez";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        onFailure = [ "${monitors.external.unit}-failure.service" ];
        serviceConfig =
          hardening
          // telegramEnv
          // {
            StateDirectory = monitors.external.unit;
          };
        script = "${externalScript}/bin/${monitors.external.unit}";
      };

      ${monitors.backup.unit} = mkIf (cfg.backup.jobs != [ ]) {
        description = "Check zanoza backup freshness per job";
        onFailure = [ "${monitors.backup.unit}-failure.service" ];
        serviceConfig =
          resticHardening
          // telegramEnv
          // {
            StateDirectory = monitors.backup.unit;
            # A wedged USB disk must not pile up runs.
            TimeoutStartSec = "30m";
          };
        script = "${backupScript}/bin/${monitors.backup.unit}";
      };

      ${monitors.verify.unit} = mkIf (cfg.backup.verify.enable && cfg.backup.jobs != [ ]) {
        description = "Verify the zanoza restic repository and restore a sample";
        onFailure = [ "${monitors.verify.unit}-failure.service" ];
        serviceConfig =
          resticHardening
          // telegramEnv
          // {
            StateDirectory = monitors.verify.unit;
            TimeoutStartSec = "4h";
            Nice = 10;
            IOSchedulingClass = "idle";
          };
        script = "${verifyScript}/bin/${monitors.verify.unit}";
      };

      "${monitors.external.unit}-failure" = mkMonitorFailureService monitors.external;
      "${monitors.backup.unit}-failure" = mkIf (cfg.backup.jobs != [ ]) (
        mkMonitorFailureService monitors.backup
      );
      "${monitors.verify.unit}-failure" = mkIf (cfg.backup.verify.enable && cfg.backup.jobs != [ ]) (
        mkMonitorFailureService monitors.verify
      );

      zanoza-external-monitor-notification-test = {
        description = "Test zanoza external monitoring notifications";
        serviceConfig = {
          Type = "oneshot";
        }
        // telegramEnv;
        script = notificationTestScript false;
      };

      zanoza-external-monitor-fallback-test = {
        description = "Test zanoza external monitoring email fallback";
        serviceConfig.Type = "oneshot";
        script = notificationTestScript true;
      };
    };
  };
}
