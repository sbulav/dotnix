# zanoza external monitoring (runs on beez)

Three independent systemd timers on beez watch zanoza from the outside. They
share one alert state machine (`pkgs.custom.monitor-state-machine`, tested by
`checks/monitor-state-machine`) and one delivery path
(`lib.custom.notifications.mkDeliverScript`: Telegram first, msmtp email when
Telegram fails), but keep separate state, metrics and schedules. A missing
backup disk therefore never delays a "zanoza is down" alert, and a network
outage never hides a stale backup.

| Unit                       | Schedule                        | Checks                                                                 | State dir                          | Metrics file              |
| -------------------------- | ------------------------------- | ---------------------------------------------------------------------- | ---------------------------------- | ------------------------- |
| `zanoza-external-monitor`  | every `probeInterval` (2m)      | TCP targets, DNS through AdGuard on zanoza, HTTPS targets              | `/var/lib/zanoza-external-monitor` | `zanoza_external.prom`    |
| `zanoza-backup-monitor`    | every `backup.checkInterval` (30m) | repository reachable, newest snapshot per backup job fresh and complete | `/var/lib/zanoza-backup-monitor`   | `zanoza_backup.prom`      |
| `zanoza-backup-verify`     | `backup.verify.onCalendar` (Sun 08:00) | `restic check --read-data-subset`, sample restore per job         | `/var/lib/zanoza-backup-verify`    | `zanoza_backup_verify.prom` |

Metrics land in the node exporter textfile directory
(`/var/lib/node_exporter/textfile_collector`) and are scraped by zanoza's
Prometheus through beez's node exporter.

## Alerting rules (all monitors)

- A check must fail `failureThreshold` (2) consecutive runs before it alerts;
  the weekly verification alerts on the first failure.
- Notifications are grouped per monitor: one message lists every alerting
  check. A new failure while others are already alerting sends an updated
  message (🆕 markers), and a full recovery sends one ✅ message.
- At most one notification attempt per `notificationMinIntervalSeconds`
  (15m). A failed delivery is retried on the next run after that interval;
  the pending state is visible as `<prefix>_notification_pending 1` and the
  unit exits non-zero when its delivery attempt failed.
- Each monitor unit has an `OnFailure=` handler (`<unit>-failure`) that
  sends the unit result and journal tail, so a monitor that crashes before
  publishing its metrics is reported instead of leaving stale gauges behind.
- Delivery order: Telegram (`telegram.proxyUrl` when set) → email via msmtp
  (`email.recipient`). Both channels failing is the only way a message is
  lost, and the unit's exit status plus `<prefix>_last_notification_success 0`
  show it; the undelivered text is then also in the unit's journal. Telegram
  texts are cut at 3900 characters, the token file is optional for the units
  (`EnvironmentFile=-…`, so a sops failure still leaves the email path), and
  the failure handlers are bounded (10 min) and ordered after
  `network-online.target`.

## Backup freshness

Freshness is read from the restic repository itself, not from file mtimes or
unit results on zanoza: a snapshot exists only when a backup completed. For
every `backup.jobs` entry the monitor runs

```sh
restic -r <repositoryPath> --password-file <passwordSecret> --no-cache --no-lock \
  snapshots --json [--tag …] [--path …]
```

takes the newest matching snapshot and requires

- its age below `staleAfterSeconds` (job override or the 36h default), and
- every `expectedPaths` entry to be present in the snapshot's `paths`
  (catches a job that "succeeded" with half its inputs missing).

The repository lives on an NTFS USB disk under autofs. Availability is
decided by `timeout mountTimeoutSeconds test -f <repo>/config`; when the disk
is not there the single `backup_repository` check fails and the jobs are
reported as unknown (`zanoza_backup_job_snapshot_age_seconds -1`), so one
root cause produces one alert. No `RequiresMountsFor=` is used anywhere.

The 30-minute probe keeps the USB disk from spinning down; accepted, the
disk is shared with other autofs users anyway and `checkInterval` is the knob.

Job selectors on beez match what zanoza's restic module writes: `opencloud`
by tag `job=opencloud` (the pre-tag `users/`-only snapshots must not count),
`immich` and `photos` by path, because tags exist only after zanoza runs the
tagged configuration.

## Backup verification

Weekly, in a window where zanoza's backup/prune units are idle (`restic check`
takes the exclusive repository lock; the prune can run until 06:35):

1. `restic check --read-data-subset=<readDataSubset>` — structure plus a
   random 5% of the pack data.
2. Per job with `verify.include`: `restic restore latest <selectors> --target
   <state>/restore-test/<job> --include <include>`, then require at least one
   regular file and, when set, `verify.expectFile`. The restored tree is
   removed afterwards. Metrics: `zanoza_backup_verify_success{step,job}`,
   `zanoza_backup_verify_restored_bytes{job}`,
   `zanoza_backup_verify_duration_seconds{step,job}`.

The restore proves the snapshot is readable end to end with the password beez
holds; it is not a full restore rehearsal (see the restic module README for
the recovery procedures).

## Metrics

```
zanoza_external_probe_success{probe,kind}          1/0 per probe
zanoza_external_monitor_healthy                    1 when no check is alerting
zanoza_external_monitor_alerting_checks            number of alerting checks
zanoza_external_monitor_notification_pending       1 when a message still has to be (re)sent
zanoza_external_monitor_last_notification_success  1 ok / 0 failed / -1 never
zanoza_external_monitor_last_run_timestamp_seconds

zanoza_backup_monitor_repository_available
zanoza_backup_job_snapshot_age_seconds{job}        -1 when unknown
zanoza_backup_job_fresh{job}
zanoza_backup_job_snapshot_timestamp_seconds{job}
zanoza_backup_monitor_*                            same state-machine gauges as above

zanoza_backup_verify_repository_available
zanoza_backup_verify_success{step="check"}
zanoza_backup_verify_success{step="restore",job}
zanoza_backup_verify_restored_bytes{job}
zanoza_backup_verify_duration_seconds{step,job}
zanoza_backup_verify_*                             same state-machine gauges as above
```

Suggested Prometheus alerts: `zanoza_backup_job_fresh == 0 for 1h`,
`zanoza_backup_monitor_repository_available == 0 for 2h`,
`time() - zanoza_backup_monitor_last_run_timestamp_seconds > 3*1800` (monitor
itself stopped), `zanoza_backup_verify_success == 0`.

## Operations

```sh
systemctl list-timers 'zanoza-*'
systemctl start zanoza-backup-monitor.service && journalctl -u zanoza-backup-monitor -n 30
cat /var/lib/node_exporter/textfile_collector/zanoza_backup.prom
cat /var/lib/zanoza-backup-monitor/notified-failures   # currently alerting checks
systemctl start zanoza-backup-verify.service            # manual verification (minutes, exclusive lock)
```

Notification tests (they send real messages; run only when the owner agreed):

```sh
systemctl start zanoza-external-monitor-notification-test.service   # Telegram, falls back to email
systemctl start zanoza-external-monitor-fallback-test.service       # email only
```

Simulating failures without touching zanoza: add a bogus `httpTargets` entry
on a test branch, or set a job's `staleAfterSeconds = 1` and start the backup
monitor twice (threshold 2); the second run alerts, reverting recovers.

## Failure boundaries

- beez down → nothing from this module; zanoza's own Prometheus loses the
  beez node exporter target (alert on `up{instance=~"beez.*"} == 0` there).
- Backup disk unmounted → `backup_repository` alert only; probes unaffected.
- Telegram unreachable → email; both unreachable → retried every 15m while the
  condition persists, visible in the metrics and unit status.
- zanoza's restic timers stopped → snapshots age out → `backup_<job>` alerts
  after 36h + 2 runs, independently of anything zanoza reports.
