{ writeShellApplication, coreutils, ... }:
# Alert state machine shared by the beez monitors (external probes, backup
# freshness, backup verification). It is deliberately free of any probe or
# delivery logic so that `checks/monitor-state-machine` can exercise every
# transition with stubbed inputs.
#
# Input: MONITOR_RESULTS, a TSV file with one line per check:
#   <name>\t<1|0>\t<detail>
# State (MONITOR_STATE_DIR): per-check consecutive failure counts and the set
# of failures the owner has already been told about.
# Output: at most one delivery through MONITOR_DELIVER <file> <subject> <prio>
# when the set of confirmed failures differs from the notified set, plus a few
# gauges appended to MONITOR_METRICS_OUT when set.
writeShellApplication {
  name = "monitor-evaluate";
  runtimeInputs = [ coreutils ];
  text = builtins.readFile ./monitor-evaluate.sh;
}
