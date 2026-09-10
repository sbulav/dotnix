# Restic backups (zanoza → beez)

Three nightly jobs push to one restic repository on beez
(`sftp:sab@192.168.92.194:/mnt/ext/backup_zanoza`, an NTFS USB disk under
autofs). Every snapshot is tagged `job=<name>` so freshness can be checked per
job instead of per repository.

| Job                                 | Runs as | When  | Paths                                                                   | Excluded                                                   |
| ----------------------------------- | ------- | ----- | ----------------------------------------------------------------------- | ---------------------------------------------------------- |
| `restic-backups-tank_opencloud`     | root    | 01:05 | `/tank/opencloud`, `/var/lib/nixos-containers/opencloud/etc/opencloud`  | `thumbnails`, `search`, external mounts (Video, Downloads) |
| `restic-backups-tank_opencloud_prune` | root  | 04:05 | forget/prune for `job=opencloud` only                                   |                                                            |
| `restic-backups-tank_immich`        | sab     | 02:05 | `/tank/immich`                                                          | `postgresql` (Immich dumps it into `backups/` itself)      |
| `restic-backups-tank_photos`        | sab     | 03:05 | `/tank/photos`                                                          |                                                            |

All jobs use `--exclude-caches --compression=max --one-file-system`.

## Why the OpenCloud job is different

- **Identity.** The POSIX driver owns the tree as `998:998` with `0750`/`0700`
  directories and writes its generated secrets to `/etc/opencloud/opencloud.yaml`
  inside the container root, mode `0600`. Running as `sab` produced
  `Fatal: nothing to backup`. The job now runs as root with a dedicated,
  restricted ssh key (`backups/restic_ssh_key` in sops; the public key is
  authorized on beez with `restrict,command="internal-sftp"`) and strict host
  key checking against `backup_host_key`. Nothing on disk was chmod'ed.
- **Consistency.** OpenCloud keeps state in NATS JetStream, the IDM BoltDB, the
  POSIX id cache and the storage tree at the same time. A live copy can be
  restored only with the id-cache re-assimilation dance. The job stops
  `container@opencloud.service` before the backup and starts it again in
  `postStop`, which systemd runs on success, failure and timeout alike.
  Pruning runs in a separate unit at 04:05 so the outage covers only the
  backup itself (a few minutes for ~21 GB incremental). `TimeoutStartSec=3h`
  bounds the worst case.
- **Metadata.** restic stores owner, mode and `user.*` extended attributes by
  default. The `user.oc.*` xattrs carry the POSIX driver's node ids and must
  survive a restore; do not restore with `--no-xattrs`.
- **Immich and photos** stay as `sab` and get `CAP_DAC_READ_SEARCH` on the
  unit (ambient capability), which lets restic traverse the `999:999 0770` and
  root-owned trees read-only without changing permissions.
- **Ordering.** The prune unit is ordered `After=` the backup unit and has its
  own 2h start timeout, so a long first full backup queues the prune instead
  of tripping over the repository lock.

Known edges:

- `/tank/opencloud/storage` (the unused decomposed-layout tree from before the
  POSIX driver switch, ~115 MB) is included on purpose: a full tree restore is
  simpler than reasoning about which of the small directories matter.
- On a brand-new host the container root does not exist until the container
  has run once; restic then exits 3 (`lstat` warning) and the first scheduled
  backup fails. Start the container once before the first backup.
- A `nixos-rebuild switch` that changes the container definition during the
  01:05–05:05 window restarts the container (`X-Restart-Triggers`) while the
  backup is reading it. Avoid deploying zanoza in that window or trigger the
  backup again afterwards.

## Recovery: OpenCloud

Restore to the same version that made the snapshot. The snapshot's
`opencloud.yaml` and the NATS/IDM state match one OpenCloud release. The
container runs `pkgs.unstable.opencloud`, not the host's stable package, so
check the *container's* version on the repo commit that was live:

```sh
nix eval --raw '.#nixosConfigurations.zanoza.config.containers.opencloud.config.services.opencloud.package.version'
```

before restoring onto a newer one.

Secrets that are *not* in the backup and come from sops instead:
`opencloud-env` (`secrets/zanoza/default.yaml`). Everything OpenCloud generated
itself is inside `/etc/opencloud/opencloud.yaml` and *is* in the backup.

1. Deploy the zanoza configuration with the OpenCloud module enabled so the
   container definition, tmpfiles rules and `opencloud-posix-storage-prepare`
   exist. Then stop the container:

   ```sh
   sudo systemctl stop container@opencloud.service
   ```

2. List snapshots for the job and pick one:

   ```sh
   sudo -E restic-tank_opencloud snapshots --tag job=opencloud
   ```

3. Restore the data tree in place (or `--target /tank/restore` first, see
   isolated restore below). Ownership and xattrs come from the snapshot:

   ```sh
   sudo -E restic-tank_opencloud restore <snapshot-id> --target / --include /tank/opencloud
   sudo -E restic-tank_opencloud restore <snapshot-id> --target / --include /var/lib/nixos-containers/opencloud/etc/opencloud
   ```

   Recreate the excluded, regenerable directories if they are missing:

   ```sh
   sudo install -d -o 998 -g 998 -m 0700 /tank/opencloud/thumbnails /tank/opencloud/search
   ```

4. Start the container. `opencloud-posix-storage-prepare` re-applies
   `998:998 0750` on the tree; the search index is rebuilt with
   `nixos-container run opencloud -- opencloud search index --all-spaces` if
   search results are missing.

   ```sh
   sudo systemctl start container@opencloud.service
   ```

5. Verify: log in, open the personal space, upload one file, check
   `journalctl -M opencloud -u opencloud -n 50` for POSIX driver errors.

The `opencloud.yaml` restore is what makes the restored data usable: the
service-account id, JWT secret, transfer secret and machine auth key in it are
what the restored IDM and storage nodes were created against. Restoring the
tree without it produces a working login with an empty, unrelated space.

## Recovery: Immich and photos

```sh
sudo -E restic-tank_immich restore <snapshot-id> --target / --include /tank/immich
sudo -E restic-tank_photos restore <snapshot-id> --target / --include /tank/photos
```

Immich's PostgreSQL is not backed up by restic; Immich writes its own dumps to
`/tank/immich/backups`, restore the newest dump into the container's database
after the files are back.

## Isolated restore test

Restore into a scratch location, never into the live tree, to prove a snapshot
is readable and complete:

```sh
sudo -E restic-tank_opencloud restore latest --tag job=opencloud \
  --target /tank/restore-test --include /var/lib/nixos-containers/opencloud/etc/opencloud
sudo -E restic-tank_opencloud restore latest --tag job=opencloud \
  --target /tank/restore-test --include "/tank/opencloud/posix-storage/users/*/Documents"
sudo getfattr -d -m 'user.oc.*' /tank/restore-test/tank/opencloud/posix-storage/users/*/Documents | head
sudo rm -rf /tank/restore-test
```

Snapshot statistics without restoring anything:

```sh
sudo -E restic-tank_opencloud stats latest --tag job=opencloud --mode restore-size
sudo -E restic-tank_opencloud ls latest --tag job=opencloud | grep opencloud.yaml
```

## Post-deploy checklist (after the first activation of this module version)

1. `sudo systemctl start restic-backups-tank_opencloud.service` during a quiet
   window and watch `journalctl -fu restic-backups-tank_opencloud`. Expect the
   container to stop, the backup to run, and the container to come back.
2. `sudo -E restic-tank_opencloud snapshots --tag job=opencloud` shows one
   snapshot with both paths.
3. Run the isolated restore test above once.
4. One-off cleanup of the old, untagged `users/`-only snapshots which the
   tag-scoped prune now ignores (keep two for reference):

   ```sh
   sudo -E restic-tank_opencloud forget --path /tank/opencloud/posix-storage/users --keep-last 2 --prune
   ```

5. Trigger `restic-backups-tank_immich` and `tank_photos` once and check they
   still succeed with the new capability set.

## Notifications

Delivery is shared with beez's external monitoring
(`lib.custom.notifications.mkDeliverScript`): Telegram first, through
`telegram.proxyUrl` (api.telegram.org is blocked directly from zanoza, the
sing-box SOCKS proxy is not), then email via `custom.containers.msmtp` to
`email.recipient` when Telegram fails. A message is lost only when both fail,
and then the notifying unit exits non-zero and shows up in
`systemctl --failed`.

- **Per-job failure alerts.** Every backup unit has its own
  `restic-backups-tank_<job>-failure.service` (`OnFailure=`), so one failing
  job alerts even when the other jobs in the same repository succeed, and the
  message names the job, the unit result and the last `telegram.errorLogLines`
  journal lines of that invocation.
- **Daily summary** at 07:15 (`restic-backups-summary`, after the worst-case
  end of the prune). A job is ✅ only if its unit finished with
  `Result=success` within the last 26 hours; otherwise it is ❌ with the
  reason (`not run since boot`, `last run Nh ago`, or the failure result) and
  its journal tail. All green is sent with low priority.
- **Timers are `Persistent=true`**, so a run missed during a reboot is made
  up instead of silently skipped until the next night.
- **Freshness from outside** (per job, from the repository itself, plus the
  weekly `restic check` and sample restore) lives on beez:
  `modules/nixos/services/zanoza-external-monitoring/README.md`. It does not
  depend on anything zanoza reports.

Manual tests (they send real messages):

```sh
sudo systemctl start restic-backups-notification-test.service   # Telegram → email fallback
sudo systemctl start restic-backups-fallback-test.service       # email only (FORCE_EMAIL_ONLY)
sudo systemctl start restic-backups-summary.service             # today's summary
```

Simulating a failure without breaking anything:
`sudo systemctl start restic-backups-tank_photos-failure.service` sends the
failure message for the photos job as if it had just failed.
