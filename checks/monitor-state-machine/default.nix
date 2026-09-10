{
  runCommand,
  callPackage,
  bash,
  coreutils,
  ...
}:
let
  monitor = callPackage ../../packages/monitor-state-machine { };
in
# Drives the alert state machine through the transitions the beez monitors
# rely on: threshold, grouped failure, unchanged-state silence, additional
# failure, partial recovery, full recovery, rate limiting and delivery retry.
runCommand "monitor-state-machine-test"
  {
    nativeBuildInputs = [
      bash
      coreutils
      monitor
    ];
  }
  ''
    set -euo pipefail
    export HOME=$TMPDIR
    state=$TMPDIR/state
    calls=$TMPDIR/calls
    bodies=$TMPDIR/bodies
    results=$TMPDIR/results
    metrics=$TMPDIR/metrics
    : >"$calls"
    : >"$bodies"

    cat >"$TMPDIR/deliver" <<EOF
    #!${bash}/bin/bash
    if [ -e "$TMPDIR/deliver-fail" ]; then exit 1; fi
    printf '%s|%s\n' "\$2" "\$3" >>"$calls"
    printf -- '----\n' >>"$bodies"
    cat "\$1" >>"$bodies"
    EOF
    chmod +x "$TMPDIR/deliver"

    export MONITOR_STATE_DIR=$state
    export MONITOR_RESULTS=$results
    export MONITOR_DELIVER=$TMPDIR/deliver
    export MONITOR_NAME="Test monitor"
    export MONITOR_HOST=testhost
    export MONITOR_FAILURE_THRESHOLD=2
    export MONITOR_MIN_INTERVAL=900
    export MONITOR_METRIC_PREFIX=test
    export MONITOR_METRICS_OUT=$metrics
    export MONITOR_HINT="hint line"

    run() {
      # run <now> <expected-rc> <results...>  (results as name=1|0)
      local now=$1 expected=$2; shift 2
      : >"$results"
      for r in "$@"; do
        printf '%s\t%s\t%s\n' "''${r%%=*}" "''${r##*=}" "detail for ''${r%%=*}" >>"$results"
      done
      : >"$metrics"
      local rc=0
      MONITOR_NOW=$now monitor-evaluate >"$TMPDIR/out" 2>&1 || rc=$?
      if [ "$rc" != "$expected" ]; then
        echo "expected rc $expected, got $rc"; cat "$TMPDIR/out"; exit 1
      fi
    }
    calls_count() { wc -l <"$calls"; }
    expect_calls() {
      if [ "$(calls_count)" != "$1" ]; then
        echo "expected $1 deliveries, got $(calls_count):"; cat "$calls"; cat "$bodies"; exit 1
      fi
    }
    expect_metric() {
      grep -qx "$1" "$metrics" || { echo "missing metric: $1"; cat "$metrics"; exit 1; }
    }
    last_body() { awk 'BEGIN{RS="----\n"} END{printf "%s", $0}' "$bodies"; }

    # 1. one failing batch is below the threshold: silence, but visible as unhealthy
    run 1000 0 a=0 b=1 c=1
    expect_calls 0
    expect_metric 'test_healthy 0'
    expect_metric 'test_alerting_checks 0'

    # 2. second consecutive failure confirms it: exactly one failure notification
    run 1120 0 a=0 b=1 c=1
    expect_calls 1
    grep -q '^\[testhost\] Test monitor failure|high$' "$calls"
    last_body | grep -q '🔥 FAILURE: 1 check(s) failing'
    last_body | grep -q '🆕❌ a: detail for a'
    last_body | grep -q 'hint line'
    expect_metric 'test_alerting_checks 1'
    expect_metric 'test_last_notification_success 1'

    # 3. unchanged failing state: no repeated noise
    run 1240 0 a=0 b=1 c=1
    run 1360 0 a=0 b=1 c=1
    expect_calls 1

    # 4. an additional check fails: silent until confirmed, then one grouped update
    run 1480 0 a=0 b=0 c=1
    expect_calls 1
    run 3000 0 a=0 b=0 c=1
    expect_calls 2
    grep -q '^\[testhost\] Test monitor changed|high$' "$calls"
    last_body | grep -q '⚠️ CHANGED: 2 check(s) failing'
    last_body | grep -q '❌ a: detail for a'
    last_body | grep -q '🆕❌ b: detail for b'

    # 5. partial recovery is reported (rate limit respected first)
    run 3100 0 a=1 b=0 c=1
    expect_calls 2
    expect_metric 'test_notification_pending 1'
    run 4000 0 a=1 b=0 c=1
    expect_calls 3
    last_body | grep -q '✅ recovered: a'
    last_body | grep -q '❌ b: detail for b'

    # 6. full recovery
    run 5000 0 a=1 b=1 c=1
    expect_calls 4
    grep -q '^\[testhost\] Test monitor recovered|low$' "$calls"
    last_body | grep -q '✅ RECOVERED'
    expect_metric 'test_healthy 1'
    expect_metric 'test_alerting_checks 0'

    # 7. healthy steady state stays silent
    run 5120 0 a=1 b=1 c=1
    run 5240 0 a=1 b=1 c=1
    expect_calls 4

    # 8. delivery failure: the run fails, the change stays pending and is retried
    touch "$TMPDIR/deliver-fail"
    run 7000 0 c=0 a=1 b=1
    run 7120 1 c=0 a=1 b=1
    expect_calls 4
    expect_metric 'test_last_notification_success 0'
    expect_metric 'test_notification_pending 1'
    rm "$TMPDIR/deliver-fail"
    run 7240 0 c=0 a=1 b=1
    expect_calls 4
    run 8100 0 c=0 a=1 b=1
    expect_calls 5
    last_body | grep -q '🆕❌ c: detail for c'
    expect_metric 'test_last_notification_success 1'
    expect_metric 'test_notification_pending 0'

    # 9. a check that disappears from the batch counts as recovered
    run 9100 0 a=1 b=1
    expect_calls 6
    last_body | grep -q '✅ RECOVERED'

    echo ok >"$out"
  ''
