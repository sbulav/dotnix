# Zanoza external monitoring

This module runs a small independent probe loop on `beez`. It does not copy the
Prometheus, Grafana, Loki, or Alertmanager stack from `zanoza`.

Every two minutes the timer checks:

- TCP/22 on zanoza's LAN address, as the host reachability signal;
- an A-record lookup through the AdGuard container on zanoza;
- Traefik and selected user-facing HTTPS routes;
- the age of the newest Restic snapshot stored in
  `/mnt/ext/backup_zanoza/snapshots` on beez.

Two consecutive failed batches produce one grouped alert. No further failure
alerts are sent while the monitor remains unhealthy. The first fully healthy
batch sends one recovery notification. Notification attempts are rate-limited
to one every 15 minutes.

Telegram is attempted first. A timeout, HTTP error, invalid Telegram response,
or missing token falls back to the existing `msmtp` Gmail relay. Both secrets
remain in `secrets/beez/default.yaml` and are materialized by SOPS.
`beez` uses zanoza's SOCKS5 listener for Telegram because direct API access is
blocked; if zanoza or that proxy is unavailable, the email fallback remains
independent and delivers the alert.

## Metrics

The service atomically writes
`/var/lib/node_exporter/textfile_collector/zanoza_external.prom`. The existing
Prometheus scrape of `beez:9100` therefore exposes:

- `zanoza_external_probe_success{probe=...,kind=...}`;
- `zanoza_external_backup_age_seconds`;
- `zanoza_external_monitor_healthy`;
- `zanoza_external_monitor_last_run_timestamp_seconds`.

Prometheus and Grafana stop receiving new samples when zanoza is completely
down, but the beez-local timer and notifications continue independently.

## Operational checks

Inspect the timer and latest result:

```bash
systemctl status zanoza-external-monitor.timer
journalctl -u zanoza-external-monitor.service --since today
cat /var/lib/node_exporter/textfile_collector/zanoza_external.prom
```

Test normal Telegram delivery with automatic email fallback:

```bash
sudo systemctl start zanoza-external-monitor-notification-test.service
```

Force and verify the email fallback without contacting Telegram:

```bash
sudo systemctl start zanoza-external-monitor-fallback-test.service
```

For an end-to-end alert/recovery test, temporarily firewall one configured test
endpoint or replace it with an unused port. Leave it unavailable for two probe
batches, confirm one grouped alert, restore it, and confirm one recovery. Do not
firewall zanoza's DNS or all HTTPS routes at once unless a full-host outage test
is intended.

## Failure boundaries

- If zanoza is lost, beez detects TCP, DNS, HTTP, and eventually backup failures
  and sends a single grouped alert.
- If beez is lost, the external signal and backup destination are both lost;
  zanoza's existing local Prometheus/Grafana and Restic service alerts remain the
  only signals.
- If Telegram is lost, beez sends the same message through email.
- If both notification providers are unavailable, the service exits non-zero and
  retries the state transition after the notification rate limit.
- A missing or unmounted backup repository is a failed backup-freshness probe;
  no Restic password is copied to beez because repository file timestamps are
  sufficient for staleness detection.
