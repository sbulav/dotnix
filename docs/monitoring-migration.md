# Monitoring on beez

Prometheus (`/var/lib/prometheus2`), Loki (`/var/lib/loki`) and Grafana
(`/var/lib/grafana/data`, mounted into the container) use beez's root NVMe.
They have no zanoza, ZFS, NFS or backup USB mount dependency. Authelia remains
on zanoza. Prometheus keeps its public hostname through zanoza's Traefik, with
an explicit backend on beez's LAN address, 192.168.92.194. Grafana is published
by beez's own Traefik container (see "Grafana ingress on beez" below), so the
dashboards do not depend on zanoza or its site being up.

## Collection and history

Alloy and node/SMART exporters run on each observed host. NUT and Authelia
remain on zanoza. Prometheus has separate `node`, `smartctl`, `nut` and
`authelia` jobs; every target carries `host` and `instance` set to its host
name. `up{host="beez",job="node"}` and the SMART equivalent are independent.
The existing optional mz targets are retained. The exporter-down alert
covers the two always-on servers, avoiding expected desktop-off alerts.

Existing rule UIDs, dashboard UIDs and Grafana's encryption key are retained.
SMART, filesystem and temperature alerts now cover both servers; the
five-disk-count, ZFS, UPS and camera-specific rules remain scoped to zanoza.
Old Prometheus data retains its original labels (including `nodes`, `beez`
and loopback instances). Queries over times before migration must use those
old selectors; no historical series are rewritten. Grafana panels use the
new labels from cutover onward. Loki keeps `host` labels and 720-hour finite
retention, with the same TSDB v13 schema and compactor settings.

## Recoverable migration

Pinned binaries at cutover: Prometheus 3.12.0, Loki 3.7.7, Grafana 13.0.7.
Both hosts use the same unchanged flake lock. A cold copy of complete state
(including WAL, index/chunks, compactor markers, SQLite and plugins) is
compatible; do not copy live SQLite or TSDB files as a final transfer.

1. Build both target systems and run the flake checks before stopping anything.
2. Record both current system generation paths, health, dashboard UIDs, and
   Prometheus/Loki query results at a fixed timestamp for later comparison.
3. Stop zanoza's `prometheus`, `loki`, and `container@grafana` services. Alloy
   remains local and reconnects to the new Loki endpoint after activation.
4. Copy complete `/var/lib/prometheus2`, `/var/lib/loki` and
   `/tank/grafana/data` into a protected staging directory on beez, preserving
   modes and metadata. Retain the source directories unchanged as rollback.
5. Install the staged directories at the paths above before target services
   start. Remap Prometheus and Loki ownership to the target service users:
   dynamic numeric allocations differ between hosts (source Loki 993:990 is
   already nix-serve on beez). Preserve Grafana container ownership 196:999.
   A temporary first-start root pre-command can perform the ownership remap
   after NixOS creates the target users. Remove it after the first start.
6. Activate beez, then zanoza's route/exporter/Alloy change. Compare fixed-time
   history queries and dashboard UIDs, service readiness, all server scrape
   targets, log ingestion, alert evaluation and notification delivery.

Expect a brief collection gap between source stop and target start. Alloy
journals remain available on the observed hosts; there is no guarantee of
zero loss for application file logs during a prolonged outage. Preserve
Alloy state on each host. Record actual cutover duration with deployment
results; never claim the gap is zero.

Rollback: stop the three beez services first, preserve their new state in a
separate directory, activate the recorded zanoza generation to restore its
local servers/routes/Alloy endpoint, then restore the recorded beez generation.
The original zanoza directories remain the pre-cutover recovery point. Do not
merge TSDB or SQLite trees. Rolling back to that checkpoint discards the
post-cutover interval from active views; keep the beez copy for later recovery.
Keep the cold source copy until the migration has been accepted.

## Administration when zanoza is down

`https://grafana.sbulav.ru` stays available: public DNS points it at beez's
site and beez's Traefik terminates it. Use Grafana's local admin credentials
from the encrypted `secrets/beez/monitoring.yaml`. Basic authentication and
the login form remain enabled; anonymous access remains disabled. OIDC login
requires zanoza and should not be selected during its outage.

Prometheus and Loki have no beez ingress. Reach them (or Grafana, should its
Traefik be down too) directly on beez by IP, using the existing SSH key:

```sh
ssh -N -L 127.0.0.1:3000:172.16.65.112:3000 -L 127.0.0.1:9090:127.0.0.1:9090 -L 127.0.0.1:3030:127.0.0.1:3030 sab@192.168.92.194
```

The tunnel ports are protected by SSH and bind locally only.

Grafana sends email directly to Gmail SMTP over STARTTLS, using its own secret
and beez's redundant DNS. Email does not use zanoza's SOCKS proxy, Traefik or
Authelia. Telegram is an additional receiver; direct Telegram is blocked on
this uplink and is not the independent delivery guarantee. The pre-existing
beez external monitor also retains its direct email fallback. Verify a clearly
marked real email test while isolating beez from zanoza, then restore connectivity.

## Build headroom

Actual Nix builders live in `nix-daemon.service`, while evaluation lives in
the cache client. Both units share `nix-builds.slice`, with an aggregate
300% CPU limit, 8 GiB memory high / 9 GiB maximum, and CPU/I/O weights 20.
Prometheus, Loki and the Grafana container each receive weights 200 and
512 MiB memory protection. This leaves roughly 2 GiB for monitoring and the
OS on the 11 GiB machine. Large builds can fail their memory ceiling; that is
preferable to starving collection. Check scrape health and alert evaluation
while a cache build is running, and inspect cgroup memory events if it fails.

## Executed migration and validation (2026-09-13)

The original rollback systems are:

- beez: `/nix/store/p30lw18nrcxvhlx22fpbg4lvqbvhhi32-nixos-system-beez-26.05.20260901.a311611`
- zanoza: `/nix/store/lhg41shnpgn18wizaaariqjgaai1lb69-nixos-system-zanoza-26.05.20260901.a311611`

A first attempt failed SSH host-key verification before activation and restored
all three original source services. After installing beez's verified public host
key in its deployment user's known-hosts file, the successful cold cutover stopped
the source at 14:12:16 UTC; target readiness and history checks passed at 14:13:00
(44 seconds), and source routing/collection deployment completed at 14:14:44.
These are bounded collection interruptions, not a zero-gap migration. Original
source data remains available; timestamps and original system paths also live in
beez's root-only `/var/lib/dotnix-monitoring-migration-47` directory.

Validation completed:

- Both affected systems and deployment closures built; formatting and Linux flake
  checks passed, including `promtool` validation of the actual Grafana alert queries.
- At timestamp `1789283030`, historical Prometheus `count(up)` remained `6`, and
  Loki `sum(count_over_time({host="zanoza"}[5m]))` remained `6801` after copying.
  All eight dashboard UIDs were preserved.
- Six always-on targets (beez node/SMART; zanoza node/SMART/NUT/Authelia) were
  independently healthy. Optional mz targets were offline, as expected.
  Loki received new logs from both servers. Grafana and Prometheus public routes
  returned healthy responses through zanoza; Traefik and Authelia remained there.
- During bounded firewall isolation of beez and its Grafana container from
  zanoza's host and container subnet, beez node/SMART stayed up, zanoza's four
  targets went down, and local log ingestion continued. Grafana's exporter alert
  evaluated successfully and entered Pending at 19:02 UTC.
- The authenticated SSH tunnel showed all eight dashboards during isolation;
  anonymous API access was denied. Grafana's real configured email receiver test
  returned `success` in 1.356 seconds while isolated, using beez DNS and direct
  SMTP. This confirms SMTP acceptance; inbox receipt was not inspected.
- The first email test exposed missing Grafana outbound NAT. Adding `ve-grafana`
  to the NAT internal interfaces restored SMTP and DNS port-forward reflection.
- A bounded Nix build ran four CPU workers inside
  `/nix.slice/nix-builds.slice/nix-daemon.service`, each using approximately 75%
  CPU under the aggregate 300% cap, while monitoring remained available. The
  parent cgroup enforced the 9 GiB memory maximum.

A live slice change needs special attention with Determinate's `KillMode=process`:
its old idle daemon worker can preserve the old cgroup across restarts. In this
migration, after builds finished, both `nix-daemon.socket` and
`determinate-nixd.socket` and the service were stopped, the identified orphaned
idle worker was terminated, and the sockets/service were restarted. Verify the
actual worker cgroup, not only `systemctl show`'s configured `Slice` field. New
boots use the configured slice normally.

Independent reviews used the pinned `agy-run` workflow with Gemini 3.1 Pro (High)
for the configuration, transfer script and NAT fix; final reviews reported no
defects. GLM-5.3 reviewed the actual exporter alert and reported no defects after
correcting the abbreviated review prompt's job selector and pending duration.

The isolation rules and recovery timers were removed after testing. Monitoring
readiness stayed healthy during the capped build, with no cgroup memory-limit or
OOM events.

## Grafana ingress on beez (2026-09-26)

The first cutover left `grafana.sbulav.ru` on zanoza's Traefik, reaching beez
through a source-filtered port forward of 3000. That defeated the purpose of
the move: a zanoza or work-site outage took the dashboards with it, and only
the SSH tunnel remained. beez now runs its own Traefik container (host network,
ports 80/443 forwarded by the home router, wildcard `*.sbulav.ru` certificate
via Cloudflare DNS-01, state under `/var/lib/traefik` owned by uid 997). The
public route carries only `secure-headers`: Authelia lives on zanoza, so the
`auth-chain` middleware would fail exactly when the route matters. Grafana's
own login guards it. Both household resolvers answer `grafana.sbulav.ru` with
beez's address; every other published name still resolves to zanoza. The
Prometheus route and the 9090/3030 host ports are unchanged.

beez was activated on this configuration on 2026-09-26; the branch was merged
into main on 2026-09-28. zanoza must be activated from that main: until then
its Traefik still publishes the old Grafana route and its resolver still
answers `grafana.sbulav.ru` with zanoza. The 3000 port forward and its FORWARD
filter no longer exist in beez's configuration, but both rules survive in the
kernel until the firewall restarts or the host reboots. The old zanoza route
works only through them; remove them with `iptables -D` once zanoza is
activated.

## Acceptance and cleanup (2026-09-28)

The migration is accepted. zanoza's pre-cutover `/var/lib/loki`,
`/var/lib/prometheus2` and the `tank/grafana` dataset are no longer a rollback
point: Prometheus's 15-day retention has passed, Loki on beez carries the
copied history, and a tarball of the old Grafana data
(`zanoza-grafana-data-precutover.tgz`) sits in beez's root-only
`/var/lib/dotnix-monitoring-migration-47`. Delete the zanoza copies.

Known limits that remain after acceptance:

- Telegram delivery from beez (Grafana contact point, external monitor, cache
  builder) is proxied through zanoza's sing-box. During a zanoza outage only
  the direct Gmail path delivers.
- The huawei-ups2000 driver reports constant `battery.charge` and
  `battery.runtime`, so the battery-low rules cannot fire; only the on-battery
  status is meaningful, and it only reaches beez while the switch has power.
