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
in
{
  options.${namespace}.containers.restic = with types; {
    enable = mkBoolOpt false "Enable the restic backup service";
    backup_user = mkOpt str "sab" "The backup user";
    backup_host = mkOpt str "192.168.92.197" "The backup server host";
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
    custom.security.sops.secrets = {
      # Backup repository password using template
      "backups/restic_odroid" = lib.custom.secrets.services.backupPassword "restic_odroid" // {
        sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
      };

      # Shared telegram bot token for notifications (UID 1000 for user services)
      "telegram-notifications-bot-token" = lib.custom.secrets.services.sharedTelegramBot 1000 // {
        sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
      };
    };
    # Run backup script on a timer start at 01:05
    services.restic.backups = {
      tank_nextcloud = {
        initialize = true;
        user = cfg.backup_user;
        passwordFile = config.sops.secrets."backups/restic_odroid".path;
        repository = "sftp:${cfg.backup_user}@${cfg.backup_host}:/mnt/ext/backup_zanoza";
        paths = [ "/tank/nextcloud/data/" ];
        exclude = [
          "/tank/nextcloud/data/appdata_*"
        ];
        extraBackupArgs = [
          "--exclude-caches"
          "--compression=max"
        ];
        timerConfig = {
          OnCalendar = "01:05";
          RandomizedDelaySec = "1h";
        };
        pruneOpts = [
          "--keep-daily 7"
          "--keep-weekly 2"
          "--keep-monthly 6"
        ];
      };
      tank_immich = {
        initialize = true;
        user = cfg.backup_user;
        passwordFile = config.sops.secrets."backups/restic_odroid".path;
        repository = "sftp:${cfg.backup_user}@${cfg.backup_host}:/mnt/ext/backup_zanoza";
        paths = [ "/tank/immich/" ];
        exclude = [
          "/tank/immich/postgresql"
        ];
        extraBackupArgs = [
          "--exclude-caches"
          "--compression=max"
        ];
        timerConfig = {
          OnCalendar = "02:05";
          RandomizedDelaySec = "1h";
        };
        pruneOpts = [
          "--keep-daily 7"
          "--keep-weekly 2"
          "--keep-monthly 6"
        ];
      };
      tank_photos = {
        initialize = true;
        user = cfg.backup_user;
        passwordFile = config.sops.secrets."backups/restic_odroid".path;
        repository = "sftp:${cfg.backup_user}@${cfg.backup_host}:/mnt/ext/backup_zanoza";
        paths = [ "/tank/photos/" ];
        extraBackupArgs = [
          "--exclude-caches"
          "--compression=max"
        ];
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
          "--keep-daily 3"
          "--keep-weekly 2"
          "--keep-monthly 6"
        ];
      };
    };
    systemd.services = mkMerge [
      # Restic backup services with failure hooks
      {
        restic-backups-tank_immich.onFailure = [ "restic-backups-telegram-failure.service" ];
        restic-backups-tank_nextcloud.onFailure = [ "restic-backups-telegram-failure.service" ];
        restic-backups-tank_photos.onFailure = [ "restic-backups-telegram-failure.service" ];
      }

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
            echo "Backup Status:"

            # Check each backup service
            for service in restic-backups-tank_nextcloud restic-backups-tank_immich restic-backups-tank_photos; do
              status=$(systemctl show $service.service --property=ExecMainStatus --value 2>/dev/null || echo "unknown")
              active=$(systemctl is-active $service.service 2>/dev/null || echo "unknown")

              # Extract backup name
              backup_name=$(echo "$service" | sed 's/restic-backups-tank_//')

              if [ "$status" = "0" ] && [ "$active" = "active" -o "$active" = "inactive" ]; then
                echo "  ✅ $backup_name"
              else
                echo "  ❌ $backup_name (exit: $status, state: $active)"
              fi
            done
          '';
        }).services
      )
    ];
  };
}
