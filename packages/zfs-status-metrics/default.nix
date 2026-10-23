{
  writeShellApplication,
  coreutils,
  jq,
  ...
}:
# Turns `zpool status -jp --json-int` into node exporter textfile metrics:
# per-vdev error counters and state, pool data errors and the last scrub or
# resilver. Reads the JSON from the file argument or stdin. It never runs
# zpool itself, so `checks/zfs-status-metrics` can feed it recorded fixtures.
writeShellApplication {
  name = "zfs-status-metrics";
  runtimeInputs = [
    coreutils
    jq
  ];
  text = ''
    jq -r -f ${./zfs-status-metrics.jq} "''${1:--}"
  '';
}
