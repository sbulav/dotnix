# Input: `zpool status -jp --json-int` (OpenZFS >= 2.2). Output: Prometheus
# text exposition. Numbers may arrive as strings (without --json-int), so every
# value goes through num.

def num: if type == "number" then . elif type == "string" then tonumber else 0 end;
def esc: tostring | gsub("\\\\"; "\\\\") | gsub("\""; "\\\"") | gsub("\n"; "\\n");
def sample($name; $labels; $value):
  {name: $name, line: "\($name){\([$labels | to_entries[] | "\(.key)=\"\(.value | esc)\""] | join(","))} \($value)"};

# Every vdev below a node, keyed by its JSON key, depth first.
def tree: (.vdevs // {}) | to_entries[] | (.value + {_key: .key}) | ., tree;

# The main tree starts below the root vdev (named like the pool). Spares are
# left out: an idle spare is AVAIL, not ONLINE, and never accumulates errors.
def pool_vdevs:
  ((.vdevs // {}) | to_entries[] | .value | tree),
  ((.logs, .special, .dedup, .l2cache) // empty | objects | to_entries[]
    | (.value + {_key: .key}) | ., tree);

def families: [
  ["zfs_vdev_errors", "Read, write and checksum errors of a vdev since the last zpool clear."],
  ["zfs_vdev_online", "Whether a vdev is ONLINE."],
  ["zfs_pool_data_errors", "Persistent data errors of a pool (zpool status error_count)."],
  ["zfs_pool_scan_end_timestamp_seconds", "End time of the last finished scrub or resilver."],
  ["zfs_pool_scan_running", "Whether a scrub or resilver is in progress."],
  ["zfs_pool_scan_errors", "Errors found by the last or current scrub or resilver."]
];

[
  .pools // {} | to_entries[] | .key as $pool | .value
  | (
      (pool_vdevs | select(._key != $pool) as $v
        | ({read: "read_errors", write: "write_errors", checksum: "checksum_errors"} | to_entries[]
            | sample("zfs_vdev_errors"; {pool: $pool, vdev: $v._key, type: .key}; $v[.value] | num)),
          sample("zfs_vdev_online"; {pool: $pool, vdev: $v._key}; if $v.state == "ONLINE" then 1 else 0 end)),
      sample("zfs_pool_data_errors"; {pool: $pool}; .error_count | num),
      (.scan_stats // empty | objects | (.function // "unknown" | ascii_downcase) as $fn
        | (select(.state == "FINISHED")
            | sample("zfs_pool_scan_end_timestamp_seconds"; {pool: $pool, function: $fn}; .end_time | num)),
          sample("zfs_pool_scan_running"; {pool: $pool, function: $fn}; if .state == "SCANNING" then 1 else 0 end),
          sample("zfs_pool_scan_errors"; {pool: $pool, function: $fn}; .errors | num))
    )
] as $samples
| families[] as [$name, $help]
| "# HELP \($name) \($help)", "# TYPE \($name) gauge",
  ($samples[] | select(.name == $name) | .line)
