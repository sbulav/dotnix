{
  pkgs,
  runCommand,
  prometheus,
  gnugrep,
  ...
}:
# Feeds recorded `zpool status -jp` output through the textfile exporter:
# healthy.json is zanoza's real pool (2026-10-23); the others are derived from
# it: a faulted member with errors (numbers as strings, as without
# --json-int), a resilver in progress and a pool that was never scanned.
runCommand "zfs-status-metrics-test"
  {
    nativeBuildInputs = [
      pkgs.custom.zfs-status-metrics
      gnugrep
      prometheus.cli
    ];
  }
  ''
    set -euo pipefail
    fixtures=${./fixtures}

    render() {
      zfs-status-metrics "$fixtures/$1.json" >"$TMPDIR/$1.prom"
      promtool check metrics <"$TMPDIR/$1.prom"
    }
    expect() {
      grep -qxF "$2" "$TMPDIR/$1.prom" || { echo "$1: missing line: $2"; cat "$TMPDIR/$1.prom"; exit 1; }
    }
    absent() {
      if grep -q "$2" "$TMPDIR/$1.prom"; then
        echo "$1: unexpected match: $2"; cat "$TMPDIR/$1.prom"; exit 1
      fi
    }

    render healthy
    expect healthy 'zfs_vdev_errors{pool="tank",vdev="raidz1-0",type="checksum"} 0'
    expect healthy 'zfs_vdev_errors{pool="tank",vdev="wwn-0x5000c500790690fc-part2",type="read"} 0'
    expect healthy 'zfs_vdev_online{pool="tank",vdev="wwn-0x50014ee26c582ec5"} 1'
    expect healthy 'zfs_pool_data_errors{pool="tank"} 0'
    expect healthy 'zfs_pool_scan_end_timestamp_seconds{pool="tank",function="scrub"} 1790804300'
    expect healthy 'zfs_pool_scan_running{pool="tank",function="scrub"} 0'
    expect healthy 'zfs_pool_scan_errors{pool="tank",function="scrub"} 0'
    # 1 raidz group + 4 disks, three counters each; the root vdev is skipped
    [ "$(grep -c '^zfs_vdev_errors{' "$TMPDIR/healthy.prom")" = 15 ]
    absent healthy 'vdev="tank"'
    absent healthy '^zfs_vdev_errors{.*} [1-9]'

    render degraded-noint
    expect degraded-noint 'zfs_vdev_errors{pool="tank",vdev="wwn-0x5000c500790690fc-part2",type="read"} 3'
    expect degraded-noint 'zfs_vdev_errors{pool="tank",vdev="wwn-0x5000c500790690fc-part2",type="write"} 1'
    expect degraded-noint 'zfs_vdev_errors{pool="tank",vdev="wwn-0x5000c500790690fc-part2",type="checksum"} 12'
    expect degraded-noint 'zfs_vdev_errors{pool="tank",vdev="raidz1-0",type="checksum"} 4'
    expect degraded-noint 'zfs_vdev_online{pool="tank",vdev="wwn-0x5000c500790690fc-part2"} 0'
    expect degraded-noint 'zfs_vdev_online{pool="tank",vdev="raidz1-0"} 0'
    expect degraded-noint 'zfs_pool_data_errors{pool="tank"} 2'
    expect degraded-noint 'zfs_pool_scan_end_timestamp_seconds{pool="tank",function="scrub"} 1790804300'

    render resilvering
    expect resilvering 'zfs_pool_scan_running{pool="tank",function="resilver"} 1'
    expect resilvering 'zfs_pool_scan_errors{pool="tank",function="resilver"} 0'
    expect resilvering 'zfs_vdev_online{pool="tank",vdev="replacing-0"} 0'
    expect resilvering 'zfs_vdev_online{pool="tank",vdev="6240739706821091864"} 0'
    expect resilvering 'zfs_vdev_online{pool="tank",vdev="wwn-0x50014ee26c582ec5"} 1'
    # a running scan has no end time yet
    absent resilvering '^zfs_pool_scan_end_timestamp_seconds{'

    render no-scan
    expect no-scan 'zfs_pool_data_errors{pool="tank"} 0'
    expect no-scan 'zfs_vdev_online{pool="tank",vdev="raidz1-0"} 1'
    absent no-scan '^zfs_pool_scan_'

    # malformed input must fail, so the service can report it
    if echo '{"pools":' | zfs-status-metrics >/dev/null 2>&1; then
      echo "malformed input did not fail"; exit 1
    fi

    echo ok >"$out"
  ''
