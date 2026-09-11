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
  cfg = config.${namespace}.containers.restic;
  opencloudCfg = config.${namespace}.containers.opencloud;

  repository = "sftp:${cfg.backup_user}@${cfg.backup_host}:/mnt/ext/backup_zanoza";
  passwordFile = config.sops.secrets."backups/restic_odroid".path;

  # nixos-containers keep each container's root filesystem here. OpenCloud
  # writes its generated secrets (opencloud.yaml) into /etc/opencloud inside
  # the container on first start, so from the host the file lives under the
  # container root, not under the bind-mounted data path.
  opencloudContainerRoot = "/var/lib/nixos-containers/opencloud";
  opencloudConfigDir = "${opencloudContainerRoot}/etc/opencloud";
  opencloudUsersDir = "${opencloudCfg.dataPath}/posix-storage/users/${opencloudCfg.userId}";

  # External mounts are bind mounts of other /tank datasets into the personal
  # space (Video, Downloads). They are not OpenCloud data and are excluded
  # explicitly, in addition to --one-file-system.
  opencloudExcludes = [
    # Regenerable caches: thumbnails are re-rendered on demand, the search
    # index is rebuilt with `opencloud search index` after a restore.
    "${opencloudCfg.dataPath}/thumbnails"
    "${opencloudCfg.dataPath}/search"
  ]
  ++ optionals (opencloudCfg.userId != "") (
    map (sub: "${opencloudUsersDir}/${sub}") (attrNames opencloudCfg.externalMounts)
  );

  # Every restic unit this module defines, for the notification scripts.
  opencloudServices = optionals opencloudCfg.enable [
    "restic-backups-tank_opencloud"
    "restic-backups-tank_opencloud_prune"
  ];
  allBackupServices = opencloudServices ++ [
    "restic-backups-tank_immich"
    "restic-backups-tank_photos"
  ];

  # The OpenCloud job runs as root (see below) and therefore cannot use the
  # backup user's ssh identity. It uses a dedicated, restricted key instead;
  # the matching public key is authorized for `backup_user` on `backup_host`
  # with `restrict,command="internal-sftp"`.
  opencloudSftpCommand = concatStringsSep " " [
    "ssh"
    "-i ${config.sops.secrets."backups/restic_ssh_key".path}"
    "-o IdentitiesOnly=yes"
    "-o BatchMode=yes"
    "-o StrictHostKeyChecking=yes"
    "-o UserKnownHostsFile=/etc/ssh/ssh_known_hosts"
    # A black-holed connection must fail fast, not sit until TimeoutStartSec
    # with the container down.
    "-o ConnectTimeout=10"
    "-o ServerAliveInterval=30"
    "-o ServerAliveCountMax=3"
    "${cfg.backup_user}@${cfg.backup_host}"
    "-s sftp"
  ];

  # All four jobs share one repository and forget/prune takes the exclusive
  # lock, so every restic invocation waits up to an hour for it instead of
  # failing (a full prune of this repository can take well over 30 minutes).
  commonBackupArgs = [
    "--exclude-caches"
    "--compression=max"
    "--one-file-system"
    "--retry-lock 1h"
  ];

  keepPolicy = [
    "--keep-daily 7"
    "--keep-weekly 2"
    "--keep-monthly 6"
  ];

  # Jobs that keep running as `backup_user`. The data trees are owned by the
  # container uids (immich 999, photos 0) with group/owner-only directories, so
  # the unit is granted CAP_DAC_READ_SEARCH: read/traverse everything without
  # changing a single permission on disk and without becoming root.
  readOnlyCapabilities = {
    AmbientCapabilities = [ "CAP_DAC_READ_SEARCH" ];
    CapabilityBoundingSet = [ "CAP_DAC_READ_SEARCH" ];
    NoNewPrivileges = true;
  };

  # --- Notifications -------------------------------------------------------
  notifyEnabled = cfg.telegram.enable || cfg.email.enable;
  hostName = config.networking.hostName;
  jobLabel = service: removePrefix "restic-backups-tank_" service;

  deliverScript = lib.custom.notifications.mkDeliverScript pkgs {
    inherit hostName;
    telegram = {
      inherit (cfg.telegram) enable chatId proxyUrl;
    };
    email = {
      inherit (cfg.email) enable recipient;
      fromName = "${hostName} restic backups";
    };
  };
  deliver = "${deliverScript}/bin/notify-deliver";
  # The leading dash keeps a missing token file from failing the unit: the
  # deliverer then falls back to email instead of sending nothing.
  telegramEnv = optionalAttrs cfg.telegram.enable {
    EnvironmentFile = "-${config.sops.secrets."telegram-notifications-bot-token".path}";
  };
  # Shared shape of every notifying unit: bounded, and never started before
  # the network is up (a boot-time catch-up run can fail within seconds).
  mkNotifyUnit =
    extra:
    {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "10min";
      }
      // telegramEnv;
    }
    // extra;

  # One handler per job (OnFailure= on a shared unit makes systemd log
  # "multiple trigger source candidates" and the handler cannot tell which
  # job failed). The message carries the unit result and the tail of the
  # failed invocation's journal.
  failureScript = pkgs.writeShellApplication {
    name = "restic-notify-failure";
    runtimeInputs = with pkgs; [
      coreutils
      systemd
    ];
    text = ''
      unit="$1"
      job="$2"
      message_file=$(mktemp)
      # shellcheck disable=SC2329
      cleanup() { rm -f "$message_file"; }
      trap cleanup EXIT
      trap 'exit 143' TERM INT
      # `systemctl show` must never abort the handler: an unknown value still
      # produces a notification.
      show() { systemctl show -p "$1" --value "$2" 2>/dev/null || echo unknown; }
      result=$(show Result "$unit")
      code=$(show ExecMainCode "$unit")
      status=$(show ExecMainStatus "$unit")
      invocation=$(show InvocationID "$unit")
      {
        printf '%s\n' "🔥 ${hostName} | Restic backup failed: $job"
        printf 'Unit: %s\nResult: %s (main process %s, status %s)\n\n' "$unit" "$result" "$code" "$status"
        printf 'Last %s journal lines:\n' ${toString cfg.telegram.errorLogLines}
        if [ -n "$invocation" ] && [ "$invocation" != unknown ]; then
          journalctl _SYSTEMD_INVOCATION_ID="$invocation" -n ${toString cfg.telegram.errorLogLines} -o cat --no-pager || true
        else
          journalctl -u "$unit" -n ${toString cfg.telegram.errorLogLines} -o cat --no-pager || true
        fi
        printf '\nInspect: journalctl -u %s\n' "$unit"
      } >"$message_file"
      ${deliver} "$message_file" "[${hostName}] restic $job failed" high
    '';
  };
  mkFailureService = service: {
    "${service}-failure" = mkNotifyUnit {
      description = "Notify about a failed ${service} run";
      script = "${failureScript}/bin/restic-notify-failure ${service}.service ${jobLabel service}";
    };
  };

  # Daily summary: a job counts as good only if its last run finished with
  # Result=success within the last 26 hours (monotonic timestamps, so this
  # also catches "never ran since boot" and timers that silently stopped).
  summaryScript = pkgs.writeShellApplication {
    name = "restic-backups-summary";
    runtimeInputs = with pkgs; [
      coreutils
      systemd
    ];
    text = ''
      message_file=$(mktemp)
      trap 'rm -f "$message_file"' EXIT
      uptime_us=$(( $(cut -d. -f1 /proc/uptime) * 1000000 ))
      max_age_us=$((26 * 3600 * 1000000))
      all_ok=1
      failed_units=()

      {
        printf '%s\n' "🖥️ ${hostName} | Restic backups"
        for unit in ${concatMapStringsSep " " (s: "${s}.service") allBackupServices}; do
          job=''${unit#restic-backups-tank_}
          job=''${job%.service}
          result=$(systemctl show -p Result --value "$unit" 2>/dev/null || echo unknown)
          state=$(systemctl show -p ActiveState --value "$unit" 2>/dev/null || echo unknown)
          exit_us=$(systemctl show -p ExecMainExitTimestampMonotonic --value "$unit" 2>/dev/null || echo 0)
          exit_us=''${exit_us:-0}
          if [ "$state" = activating ]; then
            # Still running (oneshot units are "activating" until they exit);
            # its own OnFailure= handler reports the outcome.
            printf '  ⏳ %s (running)\n' "$job"
          elif ! [ "$exit_us" -eq "$exit_us" ] 2>/dev/null || [ "$exit_us" -eq 0 ]; then
            # Never ran since this boot. That is only evidence of a problem
            # once the host has been up longer than the job's own period:
            # before that the job may simply not have been due yet, and a
            # Persistent=true catch-up can still be waiting in its jitter
            # window (its next elapse then even reads in the past).
            timer="''${unit%.service}.timer"
            # An empty or zero value (monotonic-only, unloaded or stopped
            # timer) must not reach `date -d`: it parses "" as today's
            # midnight instead of failing. `date` comes from coreutils and
            # LC_ALL=C matches systemd's always-English timestamps.
            next=$(systemctl show -p NextElapseUSecRealtime --value "$timer" 2>/dev/null || true)
            next_s=0
            if [ -n "$next" ] && [ "$next" != 0 ]; then
              next_s=$(LC_ALL=C date -d "$next" +%s 2>/dev/null || echo 0)
            fi
            if [ "$next_s" -gt 0 ] && [ "$uptime_us" -lt "$max_age_us" ]; then
              printf '  ⏳ %s (scheduled, no run since boot %sh ago)\n' "$job" $((uptime_us / 3600000000))
            else
              printf '  ❌ %s (not run since boot)\n' "$job"
              all_ok=0
              failed_units+=("$unit")
            fi
          elif [ $((uptime_us - exit_us)) -gt "$max_age_us" ]; then
            printf '  ❌ %s (last run %sh ago)\n' "$job" $(( (uptime_us - exit_us) / 3600000000 ))
            all_ok=0
            failed_units+=("$unit")
          elif [ "$result" != success ]; then
            printf '  ❌ %s (%s)\n' "$job" "$result"
            all_ok=0
            failed_units+=("$unit")
          else
            printf '  ✅ %s\n' "$job"
          fi
        done
        for unit in "''${failed_units[@]}"; do
          printf '\nLast %s lines of %s:\n' ${toString cfg.telegram.errorLogLines} "$unit"
          journalctl -u "$unit" -n ${toString cfg.telegram.errorLogLines} -o cat --no-pager || true
        done
      } >"$message_file"

      if [ "$all_ok" = 1 ]; then
        ${deliver} "$message_file" "[${hostName}] restic backups OK" low
      else
        ${deliver} "$message_file" "[${hostName}] restic backups need attention" high
      fi
    '';
  };

  notificationTestScript = pkgs.writeShellApplication {
    name = "restic-notification-test";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      mode=''${1:-}
      case "$mode" in
        telegram) channel="Telegram with automatic email fallback" ;;
        email-only) channel="forced email fallback" ;;
        *)
          echo "usage: restic-notification-test <telegram|email-only>" >&2
          exit 2
          ;;
      esac
      message_file=$(mktemp)
      # shellcheck disable=SC2329
      cleanup() { rm -f "$message_file"; }
      trap cleanup EXIT
      trap 'exit 143' TERM INT
      printf '%s\n' \
        "🧪 ${hostName} | Restic backups" \
        "Notification test ($channel)." \
        >"$message_file"
      if [ "$mode" = email-only ]; then
        export FORCE_EMAIL_ONLY=true
      fi
      ${deliver} \
        "$message_file" \
        "[${hostName}] restic notification test" \
        low
    '';
  };
in
{
  options.${namespace}.containers.restic = with types; {
    enable = mkBoolOpt false "Enable the restic backup service";
    backup_user =
      mkOpt str "sab"
        "The backup user (local unit user for immich/photos and remote sftp login)";
    backup_host = mkOpt str "192.168.92.197" "The backup server host";
    backup_host_key =
      mkOpt str ""
        "SSH host public key of backup_host, e.g. \"ssh-ed25519 AAAA...\". Required for the root-run OpenCloud job (strict host key checking)";
    secret_file = mkOpt str "secrets/zanoza/default.yaml" "SOPS secret to get creds from";

    # Notifications: Telegram first, email through msmtp when Telegram fails.
    telegram = {
      enable = mkBoolOpt true "Try Telegram first for failure notifications and the daily summary";
      chatId = mkOpt str "681806836" "Telegram chat ID for notifications";
      proxyUrl =
        mkOpt str ""
          "Optional curl proxy URL for api.telegram.org (zanoza reaches it only through the sing-box SOCKS proxy)";
      errorLogLines =
        mkOpt int 10
          "Number of journal lines from the failed unit to include in a notification";
      enableTest = mkBoolOpt true "Provide manual notification test units";
    };
    email = {
      enable = mkBoolOpt true "Fall back to email (custom.containers.msmtp) when Telegram delivery fails";
      recipient = mkOpt str "bulavintsev.sergey@gmail.com" "Fallback notification recipient";
    };
  };

  imports = [
  ];

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !opencloudCfg.enable || cfg.backup_host_key != "";
        message = "custom.containers.restic.backup_host_key must be set: the OpenCloud backup job runs as root with strict host key checking";
      }
      {
        assertion = !cfg.email.enable || config.${namespace}.containers.msmtp.enable;
        message = "custom.containers.restic.email.enable requires custom.containers.msmtp.enable (the fallback sends through msmtp)";
      }
    ];

    custom.security.sops.secrets = {
      # Backup repository password using template
      "backups/restic_odroid" = lib.custom.secrets.services.backupPassword "restic_odroid" // {
        sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
      };

      # Dedicated ssh identity for the root-run OpenCloud job (root-owned 0400)
      "backups/restic_ssh_key" = {
        sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
        owner = "root";
        group = "root";
        mode = "0400";
      };

      # Shared telegram bot token for notifications (UID 1000 for user services)
      "telegram-notifications-bot-token" = mkIf cfg.telegram.enable (
        lib.custom.secrets.services.sharedTelegramBot 1000
        // {
          sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
        }
      );
    };

    # Pin the backup host key so the root job can use StrictHostKeyChecking=yes
    # without a per-user known_hosts file.
    programs.ssh.knownHosts = mkIf (cfg.backup_host_key != "") {
      "${cfg.backup_host}".publicKey = cfg.backup_host_key;
    };

    # Run backup script on a timer start at 01:05
    services.restic.backups = {
      # OpenCloud (POSIX storage driver). Requirements this job meets:
      #  - identity: runs as root. The tree is 998:998 with 0750/0700 dirs and
      #    the generated opencloud.yaml is 0600; the backup must read them
      #    without widening permissions, and stopping/starting the container
      #    needs root anyway.
      #  - coverage: whole data path (users, indexes, uploads, idm, nats,
      #    storage, proxy, locks) plus /etc/opencloud from the container root.
      #  - consistency: the container is stopped for the duration of the
      #    backup (backupPrepareCommand) and started again in postStop, which
      #    systemd runs whether the backup succeeded, failed or timed out.
      #    Pruning is a separate unit so downtime covers only the backup.
      #  - metadata: restic stores owner/mode and user.* xattrs (user.oc.*
      #    carry the POSIX driver's node ids) by default.
      tank_opencloud = mkIf opencloudCfg.enable {
        initialize = true;
        user = "root";
        inherit passwordFile repository;
        extraOptions = [ ''sftp.command="${opencloudSftpCommand}"'' ];
        paths = [
          opencloudCfg.dataPath
          opencloudConfigDir
        ];
        exclude = opencloudExcludes;
        extraBackupArgs = commonBackupArgs ++ [ "--tag job=opencloud" ];
        backupPrepareCommand = ''
          systemctl stop container@opencloud.service
        '';
        backupCleanupCommand = ''
          systemctl start container@opencloud.service
        '';
        timerConfig = {
          OnCalendar = "01:05";
          Persistent = true;
          RandomizedDelaySec = "1h";
        };
      };

      # Forget/prune for the OpenCloud job, tag-scoped so snapshots of the
      # other jobs and the pre-2026-09 untagged users/-only snapshots are
      # left alone (see README for the one-off cleanup of the latter).
      tank_opencloud_prune = mkIf opencloudCfg.enable {
        user = "root";
        inherit passwordFile repository;
        extraOptions = [ ''sftp.command="${opencloudSftpCommand}"'' ];
        timerConfig = {
          OnCalendar = "04:05";
          Persistent = true;
          RandomizedDelaySec = "30m";
        };
        pruneOpts = [
          "--tag job=opencloud"
          "--group-by host,tags"
          "--retry-lock 1h"
        ]
        ++ keepPolicy;
      };

      tank_immich = {
        initialize = true;
        user = cfg.backup_user;
        inherit passwordFile repository;
        paths = [ "/tank/immich/" ];
        exclude = [
          "/tank/immich/postgresql"
        ];
        extraBackupArgs = commonBackupArgs ++ [ "--tag job=immich" ];
        timerConfig = {
          OnCalendar = "02:05";
          Persistent = true;
          RandomizedDelaySec = "1h";
        };
        pruneOpts = [
          "--path /tank/immich"
          "--retry-lock 1h"
        ]
        ++ keepPolicy;
      };

      tank_photos = {
        initialize = true;
        user = cfg.backup_user;
        inherit passwordFile repository;
        paths = [ "/tank/photos/" ];
        extraBackupArgs = commonBackupArgs ++ [ "--tag job=photos" ];
        timerConfig = {
          OnCalendar = "03:05";
          Persistent = true;
          RandomizedDelaySec = "1h";
        };
        # --keep-last n keep the n last (most recent) snapshots.
        # --keep-hourly n for the last n hours which have one or more snapshots, keep only the most recent one for each hour.
        # --keep-daily n for the last n days which have one or more snapshots, keep only the most recent one for each day.
        # --keep-weekly n for the last n weeks which have one or more snapshots, keep only the most recent one for each week.
        # --keep-monthly n for the last n months which have one or more snapshots, keep only the most recent one for each month.
        pruneOpts = [
          "--path /tank/photos"
          "--retry-lock 1h"
          "--keep-daily 3"
          "--keep-weekly 2"
          "--keep-monthly 6"
        ];
      };
    };

    # Daily summary timer
    systemd.timers = mkIf notifyEnabled {
      "restic-backups-summary" = {
        description = "Daily Restic backup summary check";
        # After the worst case of the night: backup until 05:05 (01:05 + 1h
        # jitter + 3h), then the queued prune with its 2h budget.
        timerConfig = {
          OnCalendar = "*-*-* 07:15:00";
          Persistent = true;
        };
        wantedBy = [ "timers.target" ];
      };
    };

    systemd.services = mkMerge [
      # Restic backup services with per-job failure hooks
      {
        restic-backups-tank_immich = {
          onFailure = mkIf notifyEnabled [ "restic-backups-tank_immich-failure.service" ];
          serviceConfig = readOnlyCapabilities;
        };
        restic-backups-tank_photos = {
          onFailure = mkIf notifyEnabled [ "restic-backups-tank_photos-failure.service" ];
          serviceConfig = readOnlyCapabilities;
        };
      }

      (mkIf opencloudCfg.enable {
        restic-backups-tank_opencloud = {
          onFailure = mkIf notifyEnabled [ "restic-backups-tank_opencloud-failure.service" ];
          # Never start a backup while the container is (re)starting, and
          # bound the outage: a hung sftp session must not keep OpenCloud
          # down until morning. postStop restarts the container on timeout.
          after = [ "container@opencloud.service" ];
          serviceConfig = {
            TimeoutStartSec = "3h";
            NoNewPrivileges = true;
          };
        };
        restic-backups-tank_opencloud_prune = {
          onFailure = mkIf notifyEnabled [ "restic-backups-tank_opencloud_prune-failure.service" ];
          # The backup may legally run until 05:05 (01:05 + 1h jitter + 3h);
          # queue the prune behind it instead of failing on the repo lock.
          # After= is the fast path: it only orders units that are started
          # together. Timers are Persistent=true with RandomizedDelaySec, so
          # after a boot they elapse at different moments and ordering alone
          # cannot serialize them; `--retry-lock` covers that case, on every
          # job. oneshot units have no start timeout by default.
          after = [
            "restic-backups-tank_opencloud.service"
            "restic-backups-tank_immich.service"
            "restic-backups-tank_photos.service"
          ];
          serviceConfig = {
            TimeoutStartSec = "2h";
            NoNewPrivileges = true;
          };
        };
      })

      # One failure handler per job
      (mkIf notifyEnabled (mkMerge (map mkFailureService allBackupServices)))

      # Daily summary service
      (mkIf notifyEnabled {
        "restic-backups-summary" = mkNotifyUnit {
          description = "Check restic backups and send daily summary";
          script = "${summaryScript}/bin/restic-backups-summary";
        };
      })

      # Manual delivery tests: `systemctl start restic-backups-notification-test`
      # exercises Telegram with the automatic fallback, `-fallback-test`
      # skips Telegram and proves the msmtp path alone.
      (mkIf (notifyEnabled && cfg.telegram.enableTest) {
        "restic-backups-notification-test" = mkNotifyUnit {
          description = "Test restic backup notifications";
          script = "${notificationTestScript}/bin/restic-notification-test telegram";
        };
      })
      (mkIf (notifyEnabled && cfg.telegram.enableTest && cfg.email.enable) {
        "restic-backups-fallback-test" = mkNotifyUnit {
          description = "Test restic backup email fallback";
          script = "${notificationTestScript}/bin/restic-notification-test email-only";
        };
      })
    ];
  };
}
