# Loki retention

`custom.containers.loki.retention` gives the Loki instance a finite retention
window. It is **off by default**: enabling it is a per-host decision whose first
compaction pass permanently deletes every chunk older than the period.

```nix
custom.containers.loki = {
  enable = true;
  retention.enable = true;      # opt in, per host
  # retention.period = "720h";  # default: 30 days
};
```

## Design

Retention is the **compactor's** job. Loki still parses a `table_manager` block
(`loki -verify-config` accepts one), but `table_manager` retention — the old
`retention_deletes_enabled` / `retention_period` pair — never applied to the TSDB
single-store path this instance uses. That is why the store kept growing: the
settings were accepted and did nothing. The block has been removed.

The mechanism, per 24h index table (`schema_config.configs[0].index.period = 24h`,
prefix `index_`):

1. Every `compaction_interval` (10m) the compactor compacts each table. Applying
   retention is a separate cadence: `apply_retention_interval` defaults to
   `compaction_interval`, and because the two are then equal Loki jitters it —
   `loki -verify-config -print-config-stderr` on this exact config prints
   `apply_retention_interval: 15m0s`. So `limits_config.retention_period` is
   applied every **15m**, not every 10m.
2. Index entries older than the period are dropped, and the chunks they referenced
   are **marked** for deletion — written as marker files, not deleted yet.
3. A sweeper deletes marked chunks only after `retention_delete_delay` (**2h**).
   That delay is the safety window (see rollback below).
4. `retention_delete_worker_count = 150` bounds the sweeper's parallelism. It is
   the upstream default written out explicitly, not a tuning decision.

`retention.period` must be a single positive Go duration; `720h` = 30 days.
There is no requirement that it be a multiple of 24h (`12h` and `30h` both
validate) — but because retention is applied per index table, the 24h index
period is the effective granularity whatever you write. A zero duration (`0s`,
`0h`, `0m0s`, ...) means "never delete" in Loki, which would silently defeat the
option — the module asserts against every spelling of it when `retention.enable`
is set.

`delete_request_store = "filesystem"` tells the compactor where to keep delete
requests and markers. It reuses the configured object store, so this state lands
under the chunks directory with an `index/` prefix — no new path to provision.

`working_directory` moved from `/var/lib/loki` to **`/var/lib/loki/compactor`**, so
the compactor's scratch space is its own subdirectory instead of being scattered
next to `chunks/` and the shipper directories.

## Storage implications

zanoza's `/var/lib/loki` as of 2026-09-11, with no retention ever applied:

| | |
| --- | --- |
| Total size | **2.6 GB** |
| Chunk files | **136,741** |
| Oldest data | 2025-01 |
| Ingest rate | ~6,000–8,500 chunks/month, ~20 KB each |

At 30 days retention the steady state is roughly **8,000 chunks ≈ 160–200 MB**.
So the first pass deletes on the order of **2.4 GB** and ~128,000 files, and the
directory stays flat after that.

The deletions are not instant: they trickle out over successive compaction cycles
(one table at a time, each 24h of data), each lagging its marking by the 2h delete
delay. Expect the reclaim to take hours, not minutes, and do not interpret a slow
`du` decline as a failure.

## Activation and rollback limits

Retention is opt-in per host, and enabling it is a deploy the owner performs —
nothing here rotates or deletes anything at build time.

**Before the first deploy with `retention.enable = true`**, decide whether the
history older than the cut-off matters. The cut-off is the deploy date minus
`retention.period`: deploying on 2026-09-11 with the default 720h keeps back to
roughly 2026-08-12 and deletes everything before it — about 20 months, back to
the oldest data from 2025-01.

Say it plainly: **the first activation with `retention.enable = true` deletes
everything older than the period.** No restic job covers `/var/lib/loki` (the jobs in
`modules/nixos/containers/restic` back up opencloud, `/tank/immich` and
`/tank/photos` only), so the copy below is the only backup that will exist:

```
sudo systemctl stop loki
sudo cp -a /var/lib/loki /tank/loki-pre-retention   # ~2.6 GB
sudo systemctl start loki
```

Beyond the 2h delete delay described below, that copy is the *only* rollback —
once the sweeper has run there is no way to recover the data.

The rollback window is narrow and one-sided:

- **Within 2h of the first marking pass**, setting `retention.enable = false` and
  redeploying prevents the marked chunks from being swept — the markers are simply
  never acted on. Data is intact.
- **After the delete delay elapses**, the chunks are gone from the filesystem.
  Disabling retention then only stops *future* deletions; it restores nothing.

Unaffected by any of this: `limits_config.reject_old_samples_max_age` stays at
**168h**. That is the *ingest* window — how old a sample may be and still be
accepted — and it is independent of retention. Do not confuse a rejected-write
error with a retention deletion.

## Monitoring

Metrics exposed by the compactor, worth a panel next to the existing Loki
dashboards:

| Metric | What it tells you |
| --- | --- |
| `loki_compactor_apply_retention_last_successful_run_timestamp_seconds` | When retention last completed. The primary health signal. |
| `loki_compactor_apply_retention_operation_total` | Retention passes attempted, by status — non-`success` increments mean it is erroring out. |
| `loki_boltdb_shipper_retention_marker_count_total` | Chunks marked for deletion. Spikes on the first pass, then tracks the daily roll-off. |
| `loki_boltdb_shipper_retention_sweeper_marker_files_current` | Marker files still pending. Should trend to ~0; a growing backlog means the sweeper cannot keep up. |
| `loki_boltdb_shipper_retention_sweeper_chunk_deleted_duration_seconds` | Per-chunk delete latency — the filesystem-pressure signal. |

Suggested alert — retention silently stopping is the failure that matters, since
the symptom is only "the disk fills up again", months later:

```
time() - loki_compactor_apply_retention_last_successful_run_timestamp_seconds > 86400
```

i.e. no successful retention run in 24h. Note this alert never fires while
retention is disabled, because the metric is not exported at all — check that the
series exists after the first deploy.

The plain check, which needs no dashboard:

```
du -sh /var/lib/loki/chunks
```

Run it before the deploy and a day after. It should drop toward a few hundred MB
and then stay put.

## Move to beez (#47)

When Loki moves to beez, retention does **not** follow automatically — the
`retention.*` options are per host and default to off, so beez would start
accumulating without a bound exactly as zanoza did.

Order of operations there:

1. Copy the chunks and the active index directory (`/var/lib/loki/chunks`,
   `/var/lib/loki/boltdb-shipper-active`) to beez **before** enabling retention,
   so the migration is a plain data move and the retention pass is not racing it.
   `boltdb-shipper-cache` does not need to move — it is a cache with
   `cache_ttl = 24h` and rebuilds itself.
2. Verify beez serves the migrated history.
3. Only then set `retention.enable = true` (and `retention.period`, if it should
   differ) on beez and deploy, applying the same pre-deploy copy and the same 2h
   rollback window described above.
