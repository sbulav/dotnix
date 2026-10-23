# Zanoza disk replacement

This runbook covers replacing a member of zanoza's `tank` pool (GitHub issue
#26). `tank` is a single RAIDZ1 vdev of four 4 TB disks: it survives one
failed disk, and a second failure during the resilver loses the pool. Nothing
here is automated. No alert offlines, replaces or shuts anything down; every
step below is run by hand.

Out of scope: proactive replacement, changing the RAIDZ1 layout, and
`zpool upgrade`. Do not run `zpool upgrade` as part of a replacement, even when
`zpool status` suggests it.

## Baseline

Revalidated read-only on 2026-10-23: `tank` ONLINE, 0 read/write/checksum
errors, last scrub 2026-10-01 repaired 0 B, `zfs-scrub.timer` monthly, ZFS
2.4.4.

| Pool member (by-id)            | Serial          | Model                      | Realloc | Pending | Offline unc. | CRC    |
| ------------------------------ | --------------- | -------------------------- | ------- | ------- | ------------ | ------ |
| `wwn-0x50014ee26c582ec5-part1` | WD-WX52D95AVXC3 | WDC WD44PURZ (replacement) | 0       | 0       | 0            | 0      |
| `wwn-0x5000c50091e6cecd-part2` | ZC13N2EF        | ST4000NM0035               | 0       | 0       | 0            | 0      |
| `wwn-0x5000c500790690fc-part2` | **ZC1AHL18**    | ST4000NM0035               | **10**  | 0       | 0            | **50** |
| `wwn-0x5000c50078ce4b1a-part2` | ZC198HPT        | ST4000NM0035               | 0       | 0       | 0            | 0      |

`ZC1AHL18`'s counts have not changed since July 2026; it is the disk to watch.
The alerts fire on growth only, so these historical counts are silent.

## Alerts

All rules live in `modules/nixos/containers/grafana/alerting/rules.json` and
are evaluated by Grafana on beez every 5 minutes. They go to the
`default-alerts` contact point (Telegram and email).

| Alert                                          | Fires when                                                                                  | Clears when                   |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------- | ----------------------------- |
| ZFS - pool not ONLINE                          | `tank` is DEGRADED, FAULTED, SUSPENDED, …                                                   | the pool is ONLINE again      |
| ZFS - vdev read, write or checksum errors      | any vdev error counter in `zpool status` is non-zero                                        | `zpool clear tank`            |
| ZFS - scrub or resilver found errors           | the last scan reported errors                                                               | the next clean scrub finishes |
| ZFS - no scrub or resilver finished in 40 days | the last scan ended over 40 days ago, or never, and none is running                         | a scrub or resilver finishes  |
| ZFS - status export failed or stopped          | `zfs-status-textfile.service` failed or has not run for 30 minutes                          | the next successful run       |
| SMART - bad sector or link counter grew        | raw Reallocated, Pending, Offline uncorrectable, Reported uncorrect or UDMA CRC grew in 24h | 24h after the last growth     |
| SMART - error log grew                         | the SMART error log grew in 24h                                                             | 24h after the last growth     |
| SMART - NVMe media errors grew                 | NVMe media errors grew in 24h                                                               | 24h after the last growth     |

The SMART alerts name the disk by `serial_number` and `model_name`; the
`device` label (`sdX`) is informational only, because the letters move between
boots. The ZFS alerts name the vdev by its `/dev/disk/by-id` name.

A growing `UDMA_CRC_Error_Count` alone usually means a bad SATA cable or port,
not a bad disk: reseat or replace the cable first and watch whether it keeps
growing.

On zanoza, the ZFS metrics come from `zfs-status-textfile.timer` (every 5
minutes), which writes
`/var/lib/node_exporter/textfile_collector/zfs-status.prom`.

## 1. Identify the failing member

On zanoza:

```sh
zpool status -P tank          # full by-id paths, error counters, scan state
lsblk -o NAME,WWN,SERIAL,MODEL,SIZE
ls -l /dev/disk/by-id/ | grep -E 'wwn-|ata-'
sudo smartctl -x /dev/disk/by-id/wwn-0x5000c500790690fc   # by WWN, not sdX
```

Match the vdev name from the alert or `zpool status` (`wwn-0x…-partN`) to its
WWN, and the WWN to the serial in `lsblk` and `smartctl -i`. Write the serial
down: it is what is printed on the disk label and what tells you which drive to
pull.

Decide whether the disk needs replacing. Read errors that `zpool status`
attributes to one disk, together with growing reallocated or pending sectors,
mean replace it. A one-off checksum error with clean SMART can be cleared and
watched (step 6) instead.

## 2. Confirm the backups are fresh

Do not start a resilver without fresh backups: the resilver reads every other
disk in full and is when a second failure is most likely.

The nightly restic jobs (see `modules/nixos/containers/restic/README.md`) push
to beez. Beez checks each job's newest snapshot every 30 minutes and alerts
when one is older than 36 hours. On beez:

```sh
systemctl status zanoza-backup-monitor.service
journalctl -u zanoza-backup-monitor.service -n 50
cat /var/lib/node_exporter/textfile_collector/zanoza_backup.prom
```

`zanoza_backup_job_fresh{job=…}` must be 1 for `opencloud`, `immich` and
`photos`, and `zanoza_backup_monitor_repository_available` must be 1. If a job
is stale, run it on zanoza first (for example
`sudo systemctl start restic-backups-tank_photos.service`; the OpenCloud job
stops the OpenCloud container while it runs) and check again.

## 3. Replace the disk

Always address disks by `/dev/disk/by-id`, never `sdX`.

If the failing disk is still present and readable, leave it in the pool and
replace it with the new disk in a free bay. ZFS then resilvers from all four
members and the redundancy is kept until it is done:

```sh
zpool replace tank wwn-0x<old>-partN /dev/disk/by-id/wwn-0x<new>
```

If there is no free bay, take the old disk offline first, swap it, then
replace it by its numeric guid (shown by `zpool status -g tank` once the disk
is gone):

```sh
zpool offline tank wwn-0x<old>-partN
# power down, swap the disk, boot
zpool status -g tank
zpool replace tank <old-guid> /dev/disk/by-id/wwn-0x<new>
```

Give `zpool replace` the whole new disk. ZFS partitions it itself and the new
member appears as `wwn-0x<new>-part1`, while the original Seagates were added
as their second partition and show `-part2`. That difference is expected.
`-f` is needed only when the new disk carries an old partition table or
filesystem label; check with `lsblk` and `wipefs -n` before forcing.

## 4. Watch the resilver

```sh
zpool status tank              # "resilver in progress", estimated time left
watch -n 60 zpool status tank
```

The pool shows DEGRADED and a `replacing-0` vdev until the resilver finishes,
so the "pool not ONLINE" alert fires during this time; that is expected.
Avoid deploying zanoza and running heavy jobs until it finishes.

## 5. Scrub afterwards

`ZED_SCRUB_AFTER_RESILVER = true` (in
`systems/x86_64-linux/zanoza/hardware-configuration.nix`) starts a scrub
automatically when the resilver completes. Check that it ran and found
nothing:

```sh
zpool status tank              # "scrub repaired 0B … with 0 errors"
```

If it did not start, run `zpool scrub tank`.

## 6. Clear the error counters

Once the cause is understood and the scrub is clean:

```sh
zpool clear tank
```

This resets the per-vdev read/write/checksum counters and clears the vdev-error
alert. It does not reset the scan result: a scan that reported errors keeps
the "scrub or resilver found errors" alert firing until the next clean scrub.

## 7. Update the baseline

Read the new member's serial and SMART counters and update the baseline table
above, with the date:

```sh
sudo smartctl -i -A /dev/disk/by-id/wwn-0x<new>
```

Record the replacement in the history below, with the `zpool history tank`
line.

## History

From `zpool history tank`:

| When                | Command                                                                            | Notes                                                                                  |
| ------------------- | ---------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| 2025-01-22 09:54:07 | `zpool replace -f tank 7734672811235084 a5ce0e25-b225-4f77-8d74-dbfe48bd6ec0`      |                                                                                        |
| 2025-01-22 15:44:57 | `zpool replace -f tank 4345521791011425257 wwn-0x5000c500a3169899`                 | brought in ZC1203QC (WWN `0x5000c500a3169899`)                                         |
| 2026-07-29 12:44:53 | `zpool replace -f tank 6240739706821091864 /dev/disk/by-id/wwn-0x50014ee26c582ec5` | replaced the failing ZC1203QC with WD Purple WD-WX52D95AVXC3, which joined as `-part1` |
