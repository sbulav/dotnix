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
  stateDirectory = "/var/lib/zanoza-external-monitor";
  textfileDirectory = "/var/lib/node_exporter/textfile_collector";

  notifyScript = pkgs.writeShellApplication {
    name = "zanoza-external-monitor-notify";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      jq
      msmtp
    ];
    text = ''
      message_file="$1"
      subject="$2"

      send_email() {
        {
          printf 'From: beez external monitor <zppfan@gmail.com>\n'
          printf 'To: %s\n' ${escapeShellArg cfg.email.recipient}
          printf 'Subject: %s\n' "$subject"
          printf 'Content-Type: text/plain; charset=UTF-8\n\n'
          cat "$message_file"
        } | msmtp -a gmail ${escapeShellArg cfg.email.recipient}
      }

      ${optionalString cfg.telegram.enable ''
        if [ "''${FORCE_EMAIL_ONLY:-false}" != true ]; then
          if [ -n "''${TELEGRAM_TOKEN:-}" ]; then
            payload=$(jq -n \
              --arg chat_id ${escapeShellArg cfg.telegram.chatId} \
              --rawfile text "$message_file" \
              '{chat_id: $chat_id, text: $text, disable_notification: false}')

            response_file=$(mktemp)
            trap 'rm -f "$response_file"' EXIT
            if curl --fail-with-body --silent --show-error \
              --connect-timeout 10 \
              --max-time 30 \
              -H 'Content-Type: application/json' \
              -d "$payload" \
              -o "$response_file" \
              "https://api.telegram.org/bot''${TELEGRAM_TOKEN}/sendMessage" \
              && jq -e '.ok == true' "$response_file" >/dev/null; then
              exit 0
            fi
            echo "Telegram delivery failed; using email fallback" >&2
          else
            echo "Telegram token is unavailable; using email fallback" >&2
          fi
        fi
      ''}

      ${
        if cfg.email.enable then
          "send_email"
        else
          ''
            echo "No notification channel delivered the alert" >&2
            exit 1
          ''
      }
    '';
  };

  monitorScript = pkgs.writeShellApplication {
    name = "zanoza-external-monitor";
    runtimeInputs = with pkgs; [
      bind.dnsutils
      coreutils
      curl
      findutils
      gnugrep
      gnused
      netcat-openbsd
    ];
    text = ''
      metrics_tmp=$(mktemp ${escapeShellArg textfileDirectory}/.zanoza_external.prom.XXXXXX)
      message_tmp=$(mktemp)
      trap 'rm -f "$metrics_tmp" "$message_tmp"' EXIT

      failures=()
      now=$(date +%s)

      cat >"$metrics_tmp" <<'EOF'
      # HELP zanoza_external_probe_success Whether an external zanoza probe succeeded.
      # TYPE zanoza_external_probe_success gauge
      EOF

      record_result() {
        local name="$1"
        local kind="$2"
        local success="$3"
        local detail="$4"

        printf 'zanoza_external_probe_success{probe="%s",kind="%s"} %s\n' \
          "$name" "$kind" "$success" >>"$metrics_tmp"
        if [ "$success" -ne 1 ]; then
          failures+=("$name: $detail")
        fi
      }

      probe_http() {
        local name="$1"
        local url="$2"

        if curl --fail --location --silent --show-error \
          --output /dev/null \
          --connect-timeout ${toString cfg.connectTimeoutSeconds} \
          --max-time ${toString cfg.probeTimeoutSeconds} \
          "$url"; then
          record_result "$name" http 1 "ok"
        else
          record_result "$name" http 0 "HTTP request failed: $url"
        fi
      }

      probe_tcp() {
        local name="$1"
        local address="$2"
        local port="$3"

        if nc -z -w ${toString cfg.connectTimeoutSeconds} "$address" "$port"; then
          record_result "$name" tcp 1 "ok"
        else
          record_result "$name" tcp 0 "TCP connection failed: $address:$port"
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
          record_result dns_resolution dns 0 \
            "${cfg.dns.server} did not resolve ${cfg.dns.name}"
        ${optionalString (cfg.dns.expectedAddress != "") ''
          elif [ "$answer" != ${escapeShellArg cfg.dns.expectedAddress} ]; then
            record_result dns_resolution dns 0 \
              "${cfg.dns.name} resolved to $answer, expected ${cfg.dns.expectedAddress}"
        ''}
        else
          record_result dns_resolution dns 1 "ok"
        fi
      }

      probe_backup() {
        local snapshots=${escapeShellArg "${cfg.backup.repositoryPath}/snapshots"}
        local latest
        local age

        if [ ! -d "$snapshots" ]; then
          printf 'zanoza_external_backup_age_seconds -1\n' >>"$metrics_tmp"
          record_result backup_freshness backup 0 \
            "Restic snapshots directory is unavailable: $snapshots"
          return
        fi

        latest=$(find "$snapshots" -type f -printf '%T@\n' 2>/dev/null \
          | sort -nr | head -n 1 | cut -d. -f1)
        if [ -z "$latest" ]; then
          printf 'zanoza_external_backup_age_seconds -1\n' >>"$metrics_tmp"
          record_result backup_freshness backup 0 \
            "Restic repository contains no snapshots"
          return
        fi

        age=$((now - latest))
        printf 'zanoza_external_backup_age_seconds %s\n' "$age" >>"$metrics_tmp"
        if [ "$age" -le ${toString cfg.backup.staleAfterSeconds} ]; then
          record_result backup_freshness backup 1 "ok"
        else
          record_result backup_freshness backup 0 \
            "newest Restic snapshot is ''${age}s old (limit: ${toString cfg.backup.staleAfterSeconds}s)"
        fi
      }

      ${concatMapStringsSep "\n" (target: ''
        probe_tcp ${escapeShellArg target.name} ${escapeShellArg target.address} ${toString target.port}
      '') cfg.tcpTargets}
      probe_dns
      ${concatMapStringsSep "\n" (target: ''
        probe_http ${escapeShellArg target.name} ${escapeShellArg target.url}
      '') cfg.httpTargets}
      probe_backup

      if [ "''${#failures[@]}" -eq 0 ]; then
        raw_state=healthy
        failure_count=0
      else
        raw_state=failed
        previous_count=$(cat ${escapeShellArg "${stateDirectory}/failure-count"} 2>/dev/null || echo 0)
        failure_count=$((previous_count + 1))
      fi

      {
        printf '# HELP zanoza_external_monitor_healthy Whether every external zanoza check passes.\n'
        printf '# TYPE zanoza_external_monitor_healthy gauge\n'
        if [ "$raw_state" = healthy ]; then
          printf 'zanoza_external_monitor_healthy 1\n'
        else
          printf 'zanoza_external_monitor_healthy 0\n'
        fi
        printf '# HELP zanoza_external_monitor_last_run_timestamp_seconds Unix timestamp of the last probe run.\n'
        printf '# TYPE zanoza_external_monitor_last_run_timestamp_seconds gauge\n'
        printf 'zanoza_external_monitor_last_run_timestamp_seconds %s\n' "$now"
      } >>"$metrics_tmp"

      chmod 0644 "$metrics_tmp"
      mv -f "$metrics_tmp" ${escapeShellArg "${textfileDirectory}/zanoza_external.prom"}

      printf '%s\n' "$failure_count" >${escapeShellArg "${stateDirectory}/failure-count"}
      printf '%s\n' "''${failures[@]}" >${escapeShellArg "${stateDirectory}/current-failures"}

      if [ "$raw_state" = failed ] \
        && [ "$failure_count" -lt ${toString cfg.failureThreshold} ]; then
        effective_state=pending
      else
        effective_state="$raw_state"
      fi

      previous_state=$(cat ${escapeShellArg "${stateDirectory}/notification-state"} 2>/dev/null || echo unknown)
      last_attempt=$(cat ${escapeShellArg "${stateDirectory}/last-notification-attempt"} 2>/dev/null || echo 0)
      should_notify=false
      notification_kind=""

      if [ "$effective_state" = failed ] && [ "$previous_state" != failed ]; then
        should_notify=true
        notification_kind=failure
      elif [ "$effective_state" = healthy ] && [ "$previous_state" = failed ]; then
        should_notify=true
        notification_kind=recovery
      fi

      if [ "$should_notify" = true ] \
        && [ $((now - last_attempt)) -lt ${toString cfg.notificationMinIntervalSeconds} ]; then
        should_notify=false
      fi

      if [ "$should_notify" = true ]; then
        printf '%s\n' "$now" >${escapeShellArg "${stateDirectory}/last-notification-attempt"}

        if [ "$notification_kind" = failure ]; then
          {
            printf '🖥️ beez | External zanoza monitor\n'
            printf '🔥 FAILURE after %s consecutive checks\n\n' "$failure_count"
            printf 'Failed checks:\n'
            printf '  ❌ %s\n' "''${failures[@]}"
            printf '\nNext alert: recovery only; inspect with journalctl -u zanoza-external-monitor.service\n'
          } >"$message_tmp"
          subject="[beez] zanoza external monitoring failure"
        else
          {
            printf '🖥️ beez | External zanoza monitor\n'
            printf '✅ RECOVERED\n\n'
            printf 'All reachability, DNS, HTTP, and backup freshness checks pass.\n'
          } >"$message_tmp"
          subject="[beez] zanoza external monitoring recovered"
        fi

        if ${notifyScript}/bin/zanoza-external-monitor-notify "$message_tmp" "$subject"; then
          printf '%s\n' "$effective_state" >${escapeShellArg "${stateDirectory}/notification-state"}
        else
          echo "All notification delivery attempts failed" >&2
          exit 1
        fi
      elif [ "$previous_state" = unknown ] && [ "$effective_state" != failed ]; then
        printf '%s\n' "$effective_state" >${escapeShellArg "${stateDirectory}/notification-state"}
      elif [ "$effective_state" = healthy ] && [ "$previous_state" != failed ]; then
        printf 'healthy\n' >${escapeShellArg "${stateDirectory}/notification-state"}
      fi
    '';
  };

  notificationTestScript = emailOnly: ''
    message_file=$(mktemp)
    trap 'rm -f "$message_file"' EXIT
    printf '%s\n' \
      "🧪 beez | External zanoza monitor" \
      "Notification test (${
        if emailOnly then "forced email fallback" else "Telegram with automatic email fallback"
      })." \
      >"$message_file"
    ${optionalString emailOnly "FORCE_EMAIL_ONLY=true "}${notifyScript}/bin/zanoza-external-monitor-notify \
      "$message_file" \
      "[beez] external monitor notification test"
  '';
in
{
  options.${namespace}.services.zanoza-external-monitoring = with types; {
    enable = mkBoolOpt false "Monitor critical zanoza endpoints independently from beez";

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
      staleAfterSeconds = mkOpt int 129600 "Maximum acceptable age of the newest Restic snapshot";
    };

    probeInterval = mkOpt str "2m" "systemd interval between probe batches";
    connectTimeoutSeconds = mkOpt int 5 "Connection timeout for individual probes";
    probeTimeoutSeconds = mkOpt int 15 "Overall timeout for individual probes";
    failureThreshold = mkOpt int 2 "Consecutive failed batches required before alerting";
    notificationMinIntervalSeconds = mkOpt int 900 "Minimum interval between notification attempts";

    telegram = {
      enable = mkBoolOpt true "Try Telegram before the email fallback";
      chatId = mkOpt str "681806836" "Telegram chat ID for alerts";
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
          cfg.tcpTargets ++ cfg.httpTargets
        );
        message = "zanoza external monitoring target names must be valid Prometheus label identifiers";
      }
      {
        assertion = !cfg.email.enable || config.${namespace}.containers.msmtp.enable;
        message = "zanoza external monitoring email fallback requires custom.containers.msmtp.enable";
      }
    ];

    sops.secrets."telegram-notifications-bot-token" = mkIf cfg.telegram.enable {
      mode = mkDefault "0400";
      owner = mkDefault "root";
      group = mkDefault "root";
    };

    services.prometheus.exporters.node = {
      enable = mkDefault true;
      extraFlags = [ "--collector.textfile.directory=${textfileDirectory}" ];
    };

    systemd.tmpfiles.rules = [
      "d ${textfileDirectory} 0755 root root -"
    ];

    systemd.timers.zanoza-external-monitor = {
      description = "Run external zanoza health probes";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "3m";
        OnUnitActiveSec = cfg.probeInterval;
        RandomizedDelaySec = "15s";
        Persistent = true;
      };
    };

    systemd.services = {
      zanoza-external-monitor = {
        description = "Monitor zanoza independently from beez";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        unitConfig.RequiresMountsFor = cfg.backup.repositoryPath;
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "zanoza-external-monitor";
          UMask = "0022";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          ReadWritePaths = [ textfileDirectory ];
        }
        // optionalAttrs cfg.telegram.enable {
          EnvironmentFile = config.sops.secrets."telegram-notifications-bot-token".path;
        };
        script = "${monitorScript}/bin/zanoza-external-monitor";
      };

      zanoza-external-monitor-notification-test = {
        description = "Test zanoza external monitoring notifications";
        serviceConfig = {
          Type = "oneshot";
        }
        // optionalAttrs cfg.telegram.enable {
          EnvironmentFile = config.sops.secrets."telegram-notifications-bot-token".path;
        };
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
