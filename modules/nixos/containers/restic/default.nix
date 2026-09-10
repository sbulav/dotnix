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

  commonBackupArgs = [
    "--exclude-caches"
    "--compression=max"
    "--one-file-system"
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

    # Telegram notifications
    telegram = {
      enable = mkBoolOpt true "Enable telegram failure notifications";
      chatId = mkOpt str "681806836" "Telegram chat ID for notifications";
      errorLogLines = mkOpt int 10 "Number of error log lines to include in notification";
      enableTest = mkBoolOpt true "Enable manual test notification service";
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
      "telegram-notifications-bot-token" = lib.custom.secrets.services.sharedTelegramBot 1000 // {
        sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
      };
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
          RandomizedDelaySec = "30m";
        };
        pruneOpts = [
          "--tag job=opencloud"
          "--group-by host,tags"
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
          RandomizedDelaySec = "1h";
        };
        pruneOpts = [ "--path /tank/immich" ] ++ keepPolicy;
      };

      tank_photos = {
        initialize = true;
        user = cfg.backup_user;
        inherit passwordFile repository;
        paths = [ "/tank/photos/" ];
        extraBackupArgs = commonBackupArgs ++ [ "--tag job=photos" ];
        timerConfig = {
          OnCalendar = "03:05";
          RandomizedDelaySec = "1h";
        };
        # --keep-last n keep the n last (most recent) snapshots.
        # --keep-hourly n for the last n hours which have one or more snapshots, keep only the most recent one for each hour.
        # --keep-daily n for the last n days which have one or more snapshots, keep only the most recent one for each day.
        # --keep-weekly n for the last n weeks which have one or more snapshots, keep only the most recent one for each week.
        # --keep-monthly n for the last n months which have one or more snapshots, keep only the most recent one for each month.
        pruneOpts = [
          "--path /tank/photos"
          "--keep-daily 3"
          "--keep-weekly 2"
          "--keep-monthly 6"
        ];
      };
    };

    # Daily summary timer
    systemd.timers = mkIf cfg.telegram.enable {
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
      # Restic backup services with failure hooks
      {
        restic-backups-tank_immich = {
          onFailure = [ "restic-backups-telegram-failure.service" ];
          serviceConfig = readOnlyCapabilities;
        };
        restic-backups-tank_photos = {
          onFailure = [ "restic-backups-telegram-failure.service" ];
          serviceConfig = readOnlyCapabilities;
        };
      }

      (mkIf opencloudCfg.enable {
        restic-backups-tank_opencloud = {
          onFailure = [ "restic-backups-telegram-failure.service" ];
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
          onFailure = [ "restic-backups-telegram-failure.service" ];
          # The backup may legally run until 05:05 (01:05 + 1h jitter + 3h);
          # queue the prune behind it instead of failing on the repo lock.
          # oneshot units have no start timeout by default.
          after = [ "restic-backups-tank_opencloud.service" ];
          serviceConfig = {
            TimeoutStartSec = "2h";
            NoNewPrivileges = true;
          };
        };
      })

      # Telegram notification services
      (mkIf cfg.telegram.enable
        (lib.custom.telegram.mkTelegramNotifications pkgs {
          serviceName = "restic-backups";
          friendlyName = "Restic Backup";
          hostName = config.system.name;
          chatId = cfg.telegram.chatId;
          secretPath = config.sops.secrets."telegram-notifications-bot-token".path;
          priority = "high";
          errorLogLines = cfg.telegram.errorLogLines;
          enableTest = cfg.telegram.enableTest;

          # Custom detail extraction for restic
          getDetailsScript = ''
            output="Backup Status:"

            # Check each backup service
            for service in ${concatStringsSep " " allBackupServices}; do
              # Get status in original format: "ExecMainStatus=0"
              status=$(systemctl show $service.service --property=ExecMainStatus 2>/dev/null || echo "ExecMainStatus=unknown")

              # Extract backup name (opencloud, opencloud_prune, immich, photos)
              backup_name=$(echo "$service" | sed 's/restic-backups-tank_//')

              # Check if status is success (ExecMainStatus=0)
              if [[ "$status" == "ExecMainStatus=0" ]]; then
                output=$(printf '%s\n  ✅ %s' "$output" "$backup_name")
              else
                output=$(printf '%s\n  ❌ %s (%s)' "$output" "$backup_name" "$status")
              fi
            done

            printf '%s' "$output"
          '';

          # Identify which services failed for log extraction
          getFailedServicesScript = ''
            failed_services=""
            for service in ${concatStringsSep " " allBackupServices}; do
              status=$(systemctl show $service.service --property=ExecMainStatus --value 2>/dev/null || echo "unknown")
              if [ "$status" != "0" ]; then
                failed_services="$failed_services $service.service"
              fi
            done
            printf '%s' "$failed_services"
          '';
        }).services
      )

      # Daily summary service
      (mkIf cfg.telegram.enable {
        "restic-backups-summary" = {
          description = "Check restic backups and send daily summary";
          serviceConfig = {
            Type = "oneshot";
            EnvironmentFile = config.sops.secrets."telegram-notifications-bot-token".path;
          };
          script = lib.custom.telegram.mkTelegramSummaryScript pkgs {
            serviceName = "restic-backups";
            friendlyName = "Restic Backup";
            hostName = config.system.name;
            chatId = cfg.telegram.chatId;
            backupServices = allBackupServices;
            successPriority = "low";
            failurePriority = "high";
            errorLogLines = cfg.telegram.errorLogLines;
          };
        };
      })
    ];
  };
}
