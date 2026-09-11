: "${MONITOR_STATE_DIR:?state directory required}"
: "${MONITOR_RESULTS:?results file required}"
: "${MONITOR_DELIVER:?delivery command required}"
monitor_name="${MONITOR_NAME:-monitor}"
host_name="${MONITOR_HOST:-$(hostname)}"
threshold="${MONITOR_FAILURE_THRESHOLD:-2}"
min_interval="${MONITOR_MIN_INTERVAL:-900}"
now="${MONITOR_NOW:-$(date +%s)}"
recovery_text="${MONITOR_RECOVERY_TEXT:-All checks pass.}"
hint="${MONITOR_HINT:-}"
metrics_out="${MONITOR_METRICS_OUT:-}"
prefix="${MONITOR_METRIC_PREFIX:-monitor}"

state="$MONITOR_STATE_DIR"
mkdir -p "$state"
counts_file="$state/failure-counts"
notified_file="$state/notified-failures"
attempt_file="$state/last-notification-attempt"
result_file="$state/last-notification-result"
message_file="$state/last-message"

join_lines() {
  if [ "$#" -gt 0 ]; then
    printf '%s\n' "$@"
  fi
}

# Consecutive failure counters: a check must fail `threshold` batches in a
# row before it is confirmed. A single pass resets its counter.
declare -A previous_counts=()
if [ -f "$counts_file" ]; then
  while IFS=$'\t' read -r name count; do
    if [ -n "$name" ]; then
      previous_counts["$name"]="$count"
    fi
  done <"$counts_file"
fi

declare -A counts=()
declare -A details=()
failing_now=0
while IFS=$'\t' read -r name ok detail; do
  if [ -z "$name" ]; then
    continue
  fi
  if [ "$ok" = 1 ]; then
    counts["$name"]=0
  else
    counts["$name"]=$((${previous_counts["$name"]:-0} + 1))
    details["$name"]="${detail:-failed}"
    failing_now=$((failing_now + 1))
  fi
done <"$MONITOR_RESULTS"

{
  for name in "${!counts[@]}"; do
    printf '%s\t%s\n' "$name" "${counts[$name]}"
  done
} | sort >"$counts_file.tmp"
mv -f "$counts_file.tmp" "$counts_file"

active=()
while IFS=$'\t' read -r name count; do
  if [ -n "$name" ] && [ "$count" -ge "$threshold" ]; then
    active+=("$name")
  fi
done <"$counts_file"

notified=()
if [ -f "$notified_file" ]; then
  mapfile -t notified <"$notified_file"
fi

active_list=$(join_lines "${active[@]}" | sort)
notified_list=$(join_lines "${notified[@]}" | sort)
new_failures=$(comm -23 <(printf '%s' "$active_list") <(printf '%s' "$notified_list"))
recovered=$(comm -13 <(printf '%s' "$active_list") <(printf '%s' "$notified_list"))

kind=""
if [ "$active_list" = "$notified_list" ]; then
  kind=""
elif [ -z "$active_list" ]; then
  kind=recovery
elif [ -z "$notified_list" ]; then
  kind=failure
else
  kind=change
fi

pending=0
delivered=-1
delivery_failed_now=0
if [ -f "$result_file" ]; then
  delivered=$(cat "$result_file")
fi

if [ -n "$kind" ]; then
  last_attempt=0
  if [ -f "$attempt_file" ]; then
    last_attempt=$(cat "$attempt_file")
  fi
  if [ $((now - last_attempt)) -lt "$min_interval" ]; then
    echo "state changed ($kind) but the last notification attempt was $((now - last_attempt))s ago; retrying after ${min_interval}s" >&2
    pending=1
    kind=""
  fi
fi

if [ -n "$kind" ]; then
  printf '%s\n' "$now" >"$attempt_file"
  case "$kind" in
    failure)
      headline=$(printf '🔥 FAILURE: %s check(s) failing' "${#active[@]}")
      subject="[$host_name] $monitor_name failure"
      priority=high
      ;;
    change)
      headline=$(printf '⚠️ CHANGED: %s check(s) failing' "${#active[@]}")
      subject="[$host_name] $monitor_name changed"
      priority=high
      ;;
    recovery)
      headline='✅ RECOVERED'
      subject="[$host_name] $monitor_name recovered"
      priority=low
      ;;
  esac

  {
    printf '🖥️ %s | %s\n%s\n' "$host_name" "$monitor_name" "$headline"
    if [ "$kind" = recovery ]; then
      printf '\n%s\n' "$recovery_text"
    else
      printf '\n'
      for name in "${active[@]}"; do
        marker='❌'
        if printf '%s\n' "$new_failures" | grep -qxF -- "$name"; then
          marker='🆕❌'
        fi
        printf '%s %s: %s\n' "$marker" "$name" "${details[$name]:-failed}"
      done
      if [ -n "$recovered" ]; then
        printf '\n'
        while IFS= read -r name; do
          printf '✅ recovered: %s\n' "$name"
        done <<<"$recovered"
      fi
    fi
    if [ -n "$hint" ]; then
      printf '\n%s\n' "$hint"
    fi
  } >"$message_file"

  if "$MONITOR_DELIVER" "$message_file" "$subject" "$priority"; then
    printf '%s' "$active_list" >"$notified_file"
    delivered=1
    echo "notification delivered ($kind)"
  else
    delivered=0
    pending=1
    delivery_failed_now=1
    echo "notification delivery failed ($kind); the state change is kept pending" >&2
  fi
  printf '%s\n' "$delivered" >"$result_file"
fi

if [ -n "$metrics_out" ]; then
  healthy=1
  if [ "$failing_now" -gt 0 ]; then
    healthy=0
  fi
  {
    printf '# HELP %s_healthy Whether every check in the last batch passed.\n' "$prefix"
    printf '# TYPE %s_healthy gauge\n' "$prefix"
    printf '%s_healthy %s\n' "$prefix" "$healthy"
    printf '# HELP %s_alerting_checks Number of checks failing for at least the failure threshold.\n' "$prefix"
    printf '# TYPE %s_alerting_checks gauge\n' "$prefix"
    printf '%s_alerting_checks %s\n' "$prefix" "${#active[@]}"
    printf '# HELP %s_notification_pending Whether a state change still has to be delivered.\n' "$prefix"
    printf '# TYPE %s_notification_pending gauge\n' "$prefix"
    printf '%s_notification_pending %s\n' "$prefix" "$pending"
    printf '# HELP %s_last_notification_success Result of the last delivery attempt (1 ok, 0 failed, -1 none yet).\n' "$prefix"
    printf '# TYPE %s_last_notification_success gauge\n' "$prefix"
    printf '%s_last_notification_success %s\n' "$prefix" "$delivered"
    printf '# HELP %s_last_run_timestamp_seconds Unix timestamp of the last evaluation.\n' "$prefix"
    printf '# TYPE %s_last_run_timestamp_seconds gauge\n' "$prefix"
    printf '%s_last_run_timestamp_seconds %s\n' "$prefix" "$now"
  } >>"$metrics_out"
fi

if [ "$delivery_failed_now" = 1 ]; then
  exit 1
fi
