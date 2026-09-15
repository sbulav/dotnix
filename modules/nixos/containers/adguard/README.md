# Household DNS redundancy

Both AdGuard instances own the same declarative filter policy and local records.
`lib/dns/default.nix` contains only household DNS data: host addresses, the two
resolver addresses, the ingress and the published service names. Service records
(including Prometheus and Grafana, which run on beez) keep pointing to the
existing ingress on 192.168.89.207; moving a backend does not move Traefik or
Authelia. A and AAAA queries must respectively return the ingress IPv4 and
NODATA, never public DNS. Add future household records to that shared file,
including remote services, and only for names Traefik actually routes.

Every module and host reads these addresses from `lib.custom.dns`; the AdGuard
module asserts that the address it serves is one of the advertised resolvers,
and the `household-dns` check asserts each resolver is served by exactly one host.

**Container address space.** The router routes 172.16.64.0/18 to zanoza. beez's
containers use 172.16.65.0/24, inside that range, so from anywhere else on the
LAN (zanoza included) they are reachable only through beez's port forwards on
192.168.92.194. Adding a container on beez that the LAN must reach means adding
a forward, or moving beez's containers to a subnet with its own router route.

## Observed topology (2026-09-12)

- zanoza: enp3s0, 192.168.89.207/24, gateway 192.168.89.1. Existing AdGuard
  172.16.64.104 is router-reachable through zanoza. Uptime was 11 days.
- beez: enp1s0, 192.168.92.194/24, gateway 192.168.92.1. enp2s0 and Wi-Fi
  were down. Uptime was 81 days; container data uses its local NVMe root.
- Each host has its own active Ethernet uplink/default gateway. The physical
  switch/power topology and whether both gateways share an upstream failure
  domain cannot be proven over SSH. Do not claim router or power redundancy.
- beez uses the distinct 172.16.65.104 container address, with TCP and UDP 53
  forwarded from 192.168.92.194. No new router container-subnet route is needed.
  The admin UI stays inside the container, with no forwarded HTTP port or
  Traefik route. zanoza's existing UI/authentication stays in place.

## Independence and policy

The resolver process bootstraps encrypted upstream names through numeric
1.1.1.2/1.0.0.2. Its container uses these same numeric addresses for filter
list downloads. Private PTR forwarding is disabled so it cannot inherit a
household resolver and form a cycle. Both hosts prefer their own AdGuard
container and ignore DHCP resolver injection. Ordinary application containers
use both household resolvers, with no public fallback; systemd-resolved handles
failover. sing-box delegates to this same system resolver.

The AdGuard DNS filter, Safe Search, upstream choices, DNSSEC and rewrites are
declarative on both instances. UI edits do not persist across restarts. The
filter list is periodically fetched independently: identical policy is ensured,
but brief list-version/cache differences during updates are possible. This
preserves the observed production policy (Cloudflare security, AdGuard and
77.88.8.8 in parallel) rather than changing upstream filtering semantics.

## Router/client rollout — required manual step

The router is outside this repository. This section is a reviewable runbook;
the owner explicitly authorized both resolver deployments and both MikroTik
DHCP DNS changes on 2026-09-12. Before changing DHCP, confirm both Ethernet paths remain
up when either server is off, reserve both host addresses, and ensure UDP/TCP53
from all household VLANs can reach both resolver endpoints.

1. Save/export the router configuration and record existing DHCP DNS, static
   routes, DNS forwarding/redirection and IPv6 RA/DHCPv6 DNS settings.
2. Deploy and verify beez first. Verify zanoza's existing 172.16.64.104 still
   answers; activate its updated configuration after beez passes the canary checks.
3. Advertise DHCP option 6 as **172.16.64.104, 192.168.92.194** on each intended
   household network. If the router is itself the advertised DNS proxy, set its
   upstreams to exactly those two and disable ISP/public fallback instead.
4. Preserve the existing route to 172.16.64.104 through 192.168.89.207. Permit
   both TCP and UDP53 to beez's LAN address; do not forward port 53 from WAN.
   Exempt resolver egress from any router rule redirecting all DNS to zanoza.
5. Remove public resolver alternatives from DHCP, router forwarding, and IPv6
   RA/DHCPv6. Align browser/device encrypted-DNS policy with household filtering.
   A router with only a single usable upstream cannot satisfy this acceptance
   criterion without changing its configuration/capability.
6. Renew one canary client's lease; inspect its effective resolver list, then
   roll out remaining clients after the checks below. Existing explicit split
   DNS on mz/nz/mba13 now uses both addresses in this repository; their separately authorized
   rebuilds are still required. DHCP alone cannot override those lists.

Do not declare household rollout complete until these manual steps and both
resolver failure cases are recorded. Clients may use either resolver at any
time; the second address is not a guaranteed idle standby.

## Validation

Without stopping anything, from each client network run against each endpoint:

```sh
for dns in 172.16.64.104 192.168.92.194; do
  dig @$dns home.sbulav.ru A +short       # 192.168.89.207
  dig @$dns home.sbulav.ru AAAA          # NOERROR, zero answers
  dig @$dns beez.sbulav.ru A +short      # 192.168.92.194
  dig @$dns prometheus.sbulav.ru A +short # 192.168.89.207
  dig @$dns example.org A
  dig @$dns doubleclick.net A            # compare blocked answers
  dig +tcp @$dns home.sbulav.ru A +short
 done
```

Compare all shared records and a representative domain from the enabled filter
list, not only the examples. A genuine public-domain lookup tests outbound DNS;
local rewrites alone do not demonstrate upstream/bootstrap independence.

In an isolated canary client's network namespace, block TCP/UDP53 to one resolver
at a time, flush its cache, and repeat internal, public and blocked-domain tests
through the client's normal resolver. Repeat inside an application container.
The test must not stop or firewall zanoza itself. Observe resolver failover delay;
short application timeouts may require retries even when resolution recovers.

After beez activation, restart only its AdGuard container and repeat cold
lookups and filter-download checks while its container has no path to zanoza's
DNS. Full machine reboots and household-wide outage drills remain separate from
these resolver-level checks; do not claim reboot resilience from evaluation alone.

## Rollback

Restore the saved router/DHCP/IPv6 configuration and renew canary leases first.
If removing beez, remove its DNS advertisement before rolling its system back
(`sudo /nix/var/nix/profiles/system-<previous-generation>-link/bin/switch-to-configuration switch`).
Restore the previous single-resolver client configuration when reverting this
patch. Public fallback in the old configuration can bypass filtering/split DNS;
restoring it is a rollback, not a successful redundancy result. No application
state or ingress placement changes are needed.

## Recorded validation (2026-09-13)

- Built zanoza, beez, mz, nz and mba13; the final resolver-host adjustment was
  rebuilt for both affected hosts. `nix flake check` passed, including
  `household-dns`, `traefik-routes` and `monitor-state-machine`.
- Deployed with deploy-rs: beez generation 34 and zanoza generation 476. Both
  hosts' generated resolv.conf now contains only their household resolvers.
  The first beez activation revealed a stale DHCP public resolver entry;
  `allow_keys='static'` fixes that across switches without deleting lease data.
- All 22 intended records returned the expected A answer and AAAA NODATA from
  both resolvers. UDP/TCP queries, public resolution and `doubleclick.net`
  blocking passed independently from the home LAN. Homepage and Prometheus
  readiness also returned HTTP 200 through direct LAN ingress.
- A private-mount glibc canary with nscd masked and a dedicated unused UID
  successfully resolved internal, public and filtered names with each resolver
  blocked in turn. Packet counters confirmed the failed endpoint was attempted;
  temporary rules were removed.
- The real homepage container's systemd-resolved passed the same two failure
  cases after cache flushes, with UDP and TCP rejection counters proving actual
  failover. Its temporary rules were removed.
- Each AdGuard service restarted successfully while its container could not
  reach the peer resolver/host, then passed cold public DNS, internal DNS,
  filtering and filter-source hostname resolution. Full physical-host reboots
  and shared router/power failure domains were not tested.
- Gemini 3.1 Pro approved the full-file review. GLM-5.3-Flash was attempted via
  OpenCode and its configured API; repeated output-budget exhaustion prevented
  a usable final verdict, so that review is **inconclusive**, not approved.

The MikroTik rollout/rollback companion is merged in
[sbulav/homelab PR 1](https://github.com/sbulav/homelab/pull/1). Actual router
DHCP changes remain blocked by SSH authentication. Repository-managed split-DNS
changes on mz/nz/mba13 also await their host activations. Therefore household
client rollout is **not complete**; issue #46 remains open for those steps.
