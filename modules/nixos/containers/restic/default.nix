{
  config,
  lib,
  namespace,
  pkgs,
  ...
}:
with lib;
with lib.custom; let
  cfg = config.${namespace}.containers.restic;
  mkNtfyScript = status: priority: hostName: ''
    echo "----------------------"
    if [[ "$status" != "SUCCESS" ]]; then
      echo "Detecting failured backups"
      status_nextcloud=$(systemctl show restic-backups-tank_nextcloud.service --property=ExecMainStatus)
      status_immich=$(systemctl show restic-backups-tank_immich.service --property=ExecMainStatus)
      status_photos=$(systemctl show restic-backups-tank_photos.service --property=ExecMainStatus)
      status_result="\n--------------\nNEXTCLOUD: $status_nextcloud\nIMMICH: $status_immich\nPHOTOS: $status_photos"
      icon="🔥"
    else
      echo "Last backup was successfull"
      status_result="$status"
      icon="✅"
    fi

    data="{\"chat_id\": \"681806836\", \"text\": \"Backups on $hostName: $icon \n PRIORITY: $priority \n BACKUP STATUS: $status_result\"}"
    echo "Sending data"
    echo "$data"
     ${lib.getExe pkgs.curl} -s -X POST \
    ┊ -H 'Content-Type: application/json' \
    ┊ -d "$data" \
    ┊ https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage
  '';
in {
  options.${namespace}.containers.restic = with types; {
    enable = mkBoolOpt false "Enable the restic backup service ;";
    backup_user = mkOpt str "sab" "The backup user";
    backup_host = mkOpt str "192.168.88.201" "The backup server host";
    # backup_paths = mkOpt (listOf str) [] "List of paths to backup";
    secret_file = mkOpt str "secrets/zanoza/default.yaml" "SOPS secret to get creds from";
  };

  config = mkIf cfg.enable {
    sops.secrets = {
      # //TODO: Telegram telegram-notifications-bot-token from grafana, is this an issue?
      "backups/restic_odroid" = {
        sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
        uid = 1000;
      };
    };
    # Run backup script on a timer start at 01:05
    services.restic.backups = {
      tank_nextcloud = {
        initialize = true;
        user = cfg.backup_user;
        passwordFile = config.sops.secrets."backups/restic_odroid".path;
        repository = "sftp:${cfg.backup_user}@${cfg.backup_host}:/mnt/ext/backup_zanoza";
        paths = ["/tank/nextcloud/data/"];
        exclude = [
          "/tank/nextcloud/data/appdata_*"
        ];
        extraBackupArgs = ["--exclude-caches" "--compression=max"];
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
        paths = ["/tank/immich/"];
        exclude = [
          "/tank/immich/postgresql"
        ];
        extraBackupArgs = ["--exclude-caches" "--compression=max"];
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
        paths = ["/tank/photos/"];
        extraBackupArgs = ["--exclude-caches" "--compression=max"];
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
    systemd.services = {
      restic-backups-tank_immich = {
        onSuccess = ["restic-ntfy-success.service"];
        onFailure = ["restic-ntfy-failure.service"];
      };
      restic-backups-tank_nextcloud = {
        onSuccess = ["restic-ntfy-success.service"];
        onFailure = ["restic-ntfy-failure.service"];
      };
      restic-backups-tank_photos = {
        onSuccess = ["restic-ntfy-success.service"];
        onFailure = ["restic-ntfy-failure.service"];
      };

      restic-ntfy-success = {
        serviceConfig.EnvironmentFile = [config.sops.secrets."telegram-notifications-bot-token".path];
        script = mkNtfyScript "SUCCESS ✅" "INFO" "${config.system.name}";
        environment = {
          status = "SUCCESS";
          priority = "INFO";
          hostName = config.system.name;
        };
      };

      restic-ntfy-failure = {
        serviceConfig.EnvironmentFile = [config.sops.secrets."telegram-notifications-bot-token".path];
        script = mkNtfyScript "SUCCESS ✅" "INFO" "${config.system.name}";
        environment = {
          status = "FAILURE";
          priority = "HIGH";
          hostName = config.system.name;
        };
      };
    };
  };
}
