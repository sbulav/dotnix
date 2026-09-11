# NixOS Cache Builder & Server

Nightly builds of the flake's NixOS configurations on beez, served to the other
machines as a signed binary cache (`nix-serve-ng`), with the exact input set
that produced them published as an adoptable *candidate*.

## Overview

Every night the builder:

1. Syncs the flake repository from GitHub (`nix-cache-builder-sync.service`)
2. Resolves the newest inputs with `nix flake update` in that clone
3. **Freezes a candidate**: the repository tree at `HEAD` plus the updated
   `flake.lock`, copied out of git into an immutable directory
4. Builds each host from that frozen tree, in the configured order, under a
   per-host timeout and a total wall-clock budget
5. Signs every successful closure and publishes it as a result generation
6. Writes the per-host outcome into the candidate's `status.json` as it goes
7. Reports and notifies from `ExecStopPost=`, so a timeout or a kill still
   produces a report
8. Serves the closures on port 5000 and the candidate metadata on port 5001

Nothing is ever adopted automatically. A machine takes the candidate's lock only
when you run `sys adopt --apply` there; until then every machine keeps building
against its own committed `flake.lock`.

Only the requested Linux configurations are built, so Darwin artifacts cannot
block the batch.

## The candidate

A *candidate* is one attempt at "this source revision with these inputs". It is
identified by

```
<UTC timestamp>-<first 12 hex of sha256(flake.lock)>
e.g. 20260911T020317Z-4f1c9a0b12de
```

and it consists of two halves:

| Where | What | Served? |
| --- | --- | --- |
| `/var/lib/nix-cache-builder/sources/<candidate-id>/` | the frozen source tree (`git archive HEAD` + the updated `flake.lock`) | **no** |
| `/var/lib/nix-cache-builder/candidates/<candidate-id>/` | `flake.lock`, `inputs.json`, `metadata.json`, `status.json` | yes, over HTTP |

All four builds run against `path:/var/lib/nix-cache-builder/sources/<id>#…`, so
a later `git fetch` or `nix flake update` in the clone cannot change what a
running batch is building.

`/var/lib/nix-cache-builder/current-candidate` holds the id of the candidate the
current run is working on; the report step reads it after the build has
finished, however it finished.

### The four published files

- **`flake.lock`** — the lock the builds actually used. This is the artifact
  `sys adopt` copies; nothing has to be transcribed by hand.
- **`inputs.json`** — input name → the `locked` object nix resolved, derived
  from that same lock. Convenient for `jq`, not authoritative.
- **`metadata.json`** — `candidate_id`, `source_rev`, `lock_sha256`,
  `flake_repo`, `flake_branch`, `started_at`, `builder_host`.
- **`status.json`** — the run: `result`, `started_at`, `finished_at`, and a
  `hosts` object with one entry per host.

No flake fingerprint is recorded: `nix flake metadata --json path:<dir>` reports
none for a plain path flake, so there is nothing honest to publish.

### States and results

Per host, in `status.json`:

| `hosts.<name>.state` | meaning |
| --- | --- |
| `pending` | not started yet |
| `running` | building right now |
| `success` | built and signed; a generation was published |
| `failed` | `nix build` (or signing) failed; older generations kept |
| `timeout` | hit `perHostTimeout` or what was left of the budget |
| `skipped-budget` | the batch ran out of `totalBudget` before this host |
| `interrupted` | written by the report step for a host still `pending`/`running` when the unit died |

For the run as a whole:

| `result` | meaning |
| --- | --- |
| `running` | the batch is in flight |
| `success` | every host succeeded and preparation was clean |
| `partial` | some hosts succeeded, or preparation was degraded |
| `failed` | no host succeeded |
| `prepare-failed` | the candidate could never be frozen; `prepare_error` says why |

A failed `nix flake update` is *degraded*, not fatal: the committed lock is
restored, the batch runs against it, and the best possible result becomes
`partial`.

## Bounds: per-host timeout and total budget

```nix
custom.services.nix-cache-builder = {
  perHostTimeout = "4h";   # one host
  totalBudget    = "10h";  # the whole batch
};
```

Each build runs under
`timeout --signal=TERM --kill-after=1m <slice>s nix build …`, where `<slice>` is
the smaller of `perHostTimeout` and the budget still left. A host with less than
five minutes of budget left is not started at all and is recorded as
`skipped-budget`. `TimeoutStartSec` is `totalBudget` + 30m, so the script's own
bound normally ends the run and systemd is only the backstop.

`hosts` is a build order, not a set — earlier entries get the budget first:

```nix
hosts = [ "zanoza" "beez" "nz" "mz" ];  # servers before desktops
```

## Result generations

A successful build writes

```
/var/cache/nix-builds/<host>-result-<candidate-id>   # this generation (a GC root)
/var/cache/nix-builds/<host>-result -> <host>-result-<candidate-id>
```

The stable `<host>-result` symlink is relative and is moved only after the
closure has been signed. A host that fails or times out removes its own
incomplete out-link and leaves both the previous generations and the stable
symlink exactly as they were — yesterday's cached closure stays served.

## Cleanup: counts first, then real store pressure

`nix-cache-cleanup.service` runs hourly and works in passes:

1. Per host, keep the newest `keepGenerations` (default 3) out-links; the
   newest and whatever `<host>-result` points at are never removed.
2. While the filesystem holding `/nix/store` has less than `minFreeGB` free
   (`df -B1 --output=avail /nix/store`, default 60 GB), release the globally
   oldest removable generation — again never the newest per host and never a
   stable target. If nothing is left to release, it logs a loud warning rather
   than deleting something it promised to keep.
3. Prune candidate directories beyond `keepCandidates` (default 10), oldest
   first, protecting `current-candidate` and the newest success, and drop
   source trees whose candidate directory is gone.
4. Repair the `latest` / `last-success` symlinks.
5. Print the retained closure sizes, measured with `nix path-info -S`.

Free space is logged before and after. The cleanup **never** runs
`nix store gc` or `nix-collect-garbage`: removing an out-link only removes a GC
root, and the space comes back when the weekly `nix.gc`
(`--delete-older-than 7d`) next runs. Closure sizes are always reported with
`nix path-info -S`, never with `du` — the store is deduplicated and `du` lies.

## Reporting

The summary and the notification are produced by a **separate report script
wired as `ExecStopPost=`**, which systemd runs on success, on failure, on
`SIGTERM`, and on a start timeout alike. It reads `$SERVICE_RESULT` and
`$EXIT_STATUS`, marks every still-`pending`/`running` host `interrupted`, writes
`finished_at` and the final `result`, and delivers the message.
`TimeoutStopSec = 10m` gives it room to do so.

If `status.json` is missing entirely, the report says *no candidate:
preparation failed* instead of pretending a batch ran.

Two more safety nets:

- `OnFailure = nix-cache-builder-failure.service` catches a failure the reporter
  itself could not report. It compares the unit's current `InvocationID` with
  `/var/lib/nix-cache-builder/.last-reported-invocation` and stays silent when
  the reporter already spoke, so a normal failure notifies once.
- Delivery goes through the shared `lib.custom.notifications.mkDeliverScript`:
  Telegram first (optionally through `telegram.proxyUrl`, e.g.
  `socks5h://192.168.89.207:20170` on beez), msmtp as the fallback when
  `email.enable` is set. The whole message is echoed to the journal either way.

`notifyOnSuccess` / `notifyOnPartialSuccess` / `notifyOnFailure` and the
`successPriority` / `failurePriority` pair still decide whether and how loudly a
given result is announced.

## Publishing the candidate

```nix
custom.services.nix-cache-builder.publish = {
  enable = true;   # off by default; on for beez
  port   = 5001;
};
```

This adds an nginx vhost rooted at the candidates directory with `autoindex on`
and opens the port. Only the four metadata files are reachable; the frozen
source trees live in `/var/lib/nix-cache-builder/sources`, outside that root.

```
http://beez.sbulav.ru:5001/                       # index of all candidates
http://beez.sbulav.ru:5001/latest/                # the newest candidate
http://beez.sbulav.ru:5001/last-success/          # the newest fully successful one
http://beez.sbulav.ru:5001/latest/status.json
http://beez.sbulav.ru:5001/latest/flake.lock
http://beez.sbulav.ru:5001/latest/inputs.json
http://beez.sbulav.ru:5001/latest/metadata.json
```

## Adoption — always manual

On the machine you want to move:

```bash
sys adopt              # show what the candidate would change
sys adopt --apply      # replace ./flake.lock with the candidate's
sudo nixos-rebuild switch --flake .   # your decision, separately
```

`sys adopt`:

- takes the candidate URL from `SYS_CANDIDATE_URL`, default
  `http://beez.sbulav.ru:5001/latest`
- fetches `status.json` and **refuses unless this host's own entry is
  `success`**
- fetches `flake.lock`, prints the per-input revision changes (or a
  `diff --unified=0` when only hashes moved)
- prints the candidate id and source revision, and warns when the local git
  `HEAD` differs from `source_rev`
- without `--apply` stops there; with `--apply` writes `flake.lock` and prints
  the rebuild command

It never builds, switches, tests or deploys, and it never touches git — commit
the adopted lock yourself if you want to keep it.

The raw equivalent, if you would rather not use the wrapper:

```bash
curl -s http://beez.sbulav.ru:5001/latest/status.json | jq '.result, .hosts'
curl -s http://beez.sbulav.ru:5001/latest/metadata.json | jq .
curl -so flake.lock.candidate http://beez.sbulav.ru:5001/latest/flake.lock
diff --unified=0 flake.lock flake.lock.candidate
mv flake.lock.candidate flake.lock
```

### When adoption does not buy you a cached build

- **Your host is not `success` in that candidate.** A `failed`, `timeout` or
  `skipped-budget` host has no closure in the cache; adopting the lock only
  means you build it yourself. `sys adopt` refuses for exactly this reason.
- **Only `cache.nixos.org` was consulted.** The builds run with
  `--substituters https://cache.nixos.org`, which *replaces* the resolved
  substituter list. Paths that came from upstream were re-signed with beez's key
  and are served from beez, but they were not built there — beez's cache is a
  mirror plus the locally built remainder, not a proof that anything was
  compiled.
- **A local `nix flake update` throws the candidate away.** The moment you
  re-resolve inputs the lock no longer matches what was built, and the closures
  in the cache stop applying. Adopt, rebuild, then update — not the other way
  round.
- **Your tree is not the candidate's tree.** Whatever your checkout changes on
  top of `source_rev` is still built locally; `sys adopt` warns when the two
  differ.
- **The last dozen derivations are always rebuilt locally.** beez builds the
  frozen candidate as a revision-less `path:` flake, while you build from a git
  checkout, so `system.configurationRevision` differs — and after `sys adopt`
  your tree is dirty, so it would differ from any clean build anyway. Measured
  on beez at `ce55251` (`nix-store -q --requisites` of both toplevel
  derivations): 6873 derivations each, of which **6860 are identical and 13
  differ** — `nixos-version`, `system-path`, `etc`, `activate`, `system-units`,
  `user-units`, `dbus-1`, `etc-nix-registry.json`, two fish-completion
  derivations, a restart trigger and the toplevel itself. None of them compile
  anything; they are substitutions and symlink trees, seconds of work. Every
  package in the closure still comes from beez. Matching the toplevel exactly
  would mean committing and pushing the candidate lock first, which this
  workflow deliberately does not do.

## Resource reservation

beez is a small machine that also backs up and monitors, so the builder runs
deliberately subordinate. The work splits across two cgroups, and this matters
more than it looks:

- **Evaluation** happens in the `nix build` client, inside
  `nix-cache-builder.service`. Evaluating four NixOS closures is where the
  gigabytes go, so the unit's memory limits land exactly where the memory is.
- **Compilation** happens in builders forked by the nix daemon, inside
  `system.slice/nix-daemon.service`. Nothing set on this unit reaches them —
  measured directly: a build's process sat in
  `/system.slice/nix-daemon.service` while the client sat in the caller's own
  slice.

So the limits are split too:

| Setting | Value | Applies to | Why |
| --- | --- | --- | --- |
| `--max-jobs` | 1 | builders | one derivation at a time, not four |
| `--cores` | 3 (on beez) | builders | leaves a core free even when nothing else runs |
| `CPUWeight` / `IOWeight` | 20 | client | a fifth of the systemd default of 100 |
| `Nice` | 10 | client | yields to interactive and scheduled work |
| `CPUQuota` | 300% | client | evaluation cannot monopolise the machine either |
| `MemoryHigh` | 6G | client | start reclaiming here |
| `MemoryMax` | 10G | client | hard ceiling; `MemoryHigh` throttles, `MemoryMax` kills |

The sync and cleanup units carry the same weights and `Nice`.

beez additionally sets `nix.daemonCPUSchedPolicy = "batch"` and
`nix.daemonIOSchedClass = "best-effort"` host-wide, which is what keeps the
daemon-side builders themselves out of the way of interactive work.

Because beez's backup and monitoring timers run at the default weight of 100,
they outrank the builder under contention: when a restic job or a monitoring
probe wants CPU or disk at the same time as a build, it gets it first, and the
build simply takes longer.

### The per-host timeout does stop the build

`timeout --signal=TERM --kill-after=1m` kills the `nix build` client, and the
daemon tears the build down with it: when the client connection drops, the
daemon worker and its builder exit. Verified on this Nix (Determinate 3.19.1)
by SIGTERMing a client mid-build — the builder was gone within seconds and
`nix-daemon.service`'s cgroup returned to idle. A timed-out host therefore
costs the next host nothing.

## Options

```nix
custom.services.nix-cache-builder = {
  enable = false;

  # Source
  flakePath   = "/var/lib/nix-cache-builder/flake";  # the clone
  stateDir    = "/var/lib/nix-cache-builder";        # clone + sources + candidates
  flakeRepo   = "git@github.com:sbulav/dotnix.git";
  flakeBranch = "main";
  flakeRef    = "git+file:///var/lib/nix-cache-builder/flake";  # manual commands only
  updateFlake = true;

  # Work
  hosts          = [ "nz" "zanoza" "mz" "beez" ];  # build order
  perHostTimeout = "4h";
  totalBudget    = "10h";
  maxJobs        = 1;     # nix --max-jobs: derivations built concurrently
  buildCores     = 0;     # nix --cores per job; 0 = every core
  buildTime      = "*-*-* 02:00:00";               # OnCalendar, +5m jitter
  remoteBuilderDisableFile = null;                 # touch it to force local builds

  # Storage
  cacheDir        = "/var/cache/nix-builds";
  keepGenerations = 3;    # per host
  keepCandidates  = 10;   # candidate metadata directories
  minFreeGB       = 60;   # release generations below this much free space

  # Serving
  cacheServer = { enable = true; port = 5000; };  # nix-serve-ng
  publish     = { enable = false; port = 5001; }; # candidate metadata

  # Reporting
  errorLogLines = 25;
  telegram = {
    enable = false;
    chatId = "681806836";
    proxyUrl = "";                 # e.g. socks5h://192.168.89.207:20170
    notifyOnSuccess = true;
    notifyOnPartialSuccess = true;
    notifyOnFailure = true;
    successPriority = "low";
    failurePriority = "high";
  };
  email = { enable = false; recipient = "…"; };  # msmtp fallback
};
```

Removed options (the module fails the evaluation with a pointer):

- `maxCacheSize` → `minFreeGB` (+ `keepGenerations`)
- `cacheServer.priority` → the client's own `system.nix.cache-servers[].priority`
- `email.notifyOnSuccess`, `email.notifyOnFailure`, `email.sendOnTelegramFailure`
  → the shared deliverer is Telegram-first with an msmtp fallback; the
  `telegram.notifyOn*` switches gate both channels

### Client options

```nix
system.nix.cache-servers = [
  {
    url = "http://beez.sbulav.ru:5000";
    key = "beez.sbulav.ru:base64key…=";
    priority = 10;  # lower number = consulted earlier
  }
];
```

## Setup

### 1. SSH key for GitHub

```bash
sudo ssh-keygen -t ed25519 -C "root@beez" -f /root/.ssh/id_ed25519 -N ""
sudo cat /root/.ssh/id_ed25519.pub
```

Add it at <https://github.com/sbulav/dotnix/settings/keys> as a **read-only**
deploy key, then check it:

```bash
sudo ssh -T git@github.com   # "Hi sbulav! You've successfully authenticated..."
```

### 2. Signing key

```bash
sudo nix-store --generate-binary-cache-key \
  beez.sbulav.ru /tmp/cache-priv-key.pem /tmp/cache-pub-key.pem
cat /tmp/cache-pub-key.pem   # distribute this one to the clients
```

### 3. Private key into SOPS

```bash
sops secrets/beez/default.yaml
```

```yaml
nix-cache-priv-key: |
  beez.sbulav.ru:AbCd1234privatekey…
```

```bash
sudo rm /tmp/cache-priv-key.pem /tmp/cache-pub-key.pem
```

### 4. Enable on the builder

```nix
custom.services.nix-cache-builder = {
  enable = true;
  hosts = [ "zanoza" "beez" "nz" "mz" ];
  buildCores = 3;  # four-core machine; leave one for everything else
  cacheServer.enable = true;
  publish.enable = true;
  telegram = {
    enable = true;
    chatId = "681806836";
    proxyUrl = "socks5h://192.168.89.207:20170";
  };
  email = {
    enable = true;
    recipient = "you@example.com";
  };
};

custom.security.sops = {
  enable = true;
  sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  defaultSopsFile = lib.snowfall.fs.get-file "secrets/beez/default.yaml";
};
```

Build it first, then deploy:

```bash
nix build .#nixosConfigurations.beez.config.system.build.toplevel
nix run nixpkgs#deploy-rs -- .#beez
```

### 5. Verify

```bash
sudo systemctl start nix-cache-builder-sync.service
sudo journalctl -u nix-cache-builder-sync.service -n 50
ls -la /var/lib/nix-cache-builder/flake/

systemctl list-timers 'nix-cache-*'
curl http://localhost:5000/nix-cache-info
curl http://localhost:5001/            # candidate index
```

### 6. First run

```bash
sudo systemctl start nix-cache-builder.service    # hours, not minutes
sudo journalctl -fu nix-cache-builder.service
```

```bash
cat /var/lib/nix-cache-builder/current-candidate
jq . /var/lib/nix-cache-builder/candidates/latest/status.json
ls -lh /var/cache/nix-builds/
```

### 7. Point the clients at the cache

```nix
system.nix.cache-servers = [
  {
    url = "http://beez.sbulav.ru:5000";
    key = "beez.sbulav.ru:AbCd1234publickey…=";
    priority = 10;
  }
];
```

Then, during a rebuild, look for `copying path … from 'http://beez.sbulav.ru:5000'`.

## Operations

```bash
# What happened last night
jq . /var/lib/nix-cache-builder/candidates/latest/status.json
sudo journalctl -u nix-cache-builder.service --since yesterday

# Which candidate is current, which was the last clean one
cat /var/lib/nix-cache-builder/current-candidate
readlink /var/lib/nix-cache-builder/candidates/last-success

# What is served right now, and how big it is
ls -l /var/cache/nix-builds/*-result
nix path-info -S /var/cache/nix-builds/nz-result
df -h /nix/store

# Run things by hand
sudo systemctl start nix-cache-builder-sync.service
sudo systemctl start nix-cache-builder.service
sudo systemctl start nix-cache-cleanup.service
sudo journalctl -u nix-cache-cleanup.service -n 50
```

Reproduce one host's build exactly as the builder ran it:

```bash
cand=$(cat /var/lib/nix-cache-builder/current-candidate)
nix build "path:/var/lib/nix-cache-builder/sources/$cand#nixosConfigurations.nz.config.system.build.toplevel" \
  --substituters https://cache.nixos.org --print-build-logs
```

## Troubleshooting

**A host keeps failing.** Its `status.json` entry carries a `note`
(`nix build exited …`, `signing failed`, `no result after 4h`). Reproduce with
the command above; the previous generation stays served meanwhile.

**The run reported nothing.** That is what `ExecStopPost=` is for — check
`journalctl -u nix-cache-builder.service` for the report block, and
`nix-cache-builder-failure.service` for the fallback notification. A missing
`status.json` means preparation never got far enough to write one.

**Hosts are `skipped-budget`.** The batch ran out of `totalBudget`. Either raise
it (and `TimeoutStartSec` follows automatically) or move the important hosts
earlier in `hosts`.

**`sys adopt` refuses.** Read the printed host table: your machine is not
`success` in that candidate. Wait for the next run or point
`SYS_CANDIDATE_URL` at an older candidate that did succeed for you, e.g.
`http://beez.sbulav.ru:5001/20260911T020317Z-4f1c9a0b12de`.

**Disk filling up.** `minFreeGB` drives the pressure loop, but the space is only
reclaimed by the weekly `nix.gc`; run `sudo nix-collect-garbage` yourself if you
need it back sooner. Lower `keepGenerations` or `keepCandidates` if the pressure
loop warns that nothing is left to release.

**Clients cannot reach the cache.**

```bash
sudo systemctl status nix-serve            # on beez
curl http://beez.sbulav.ru:5000/nix-cache-info
curl http://beez.sbulav.ru:5001/           # candidates, if publish.enable
```

**SOPS decryption fails.**

```bash
ls -la /etc/ssh/ssh_host_ed25519_key
sudo sops -d secrets/beez/default.yaml
ls -la /run/secrets/nix-cache-priv-key
```

## Security notes

- The signing key is SOPS-encrypted and materialised as `0400 root:root`.
- Every published closure is signed with `nix store sign --recursive`.
- The GitHub deploy key is read-only; the builder never pushes, and never
  commits the candidate lock.
- Ports 5000 and 5001 are opened on the host firewall. Both serve read-only
  data with no authentication — keep them on the LAN, or in front of your own
  network boundary.
- Port 5001 exposes metadata only. Source trees are deliberately outside the
  nginx root.

## FAQ

**Does the builder push `flake.lock` back to GitHub?**
No. It publishes the lock it used as a candidate; you adopt it on the machine
you choose, with `sys adopt --apply`, and commit it yourself if you want to.

**What if an input update fails?**
The committed lock is restored, the batch runs against it, and the run is
reported as `partial` at best; `prepare_degraded` is set in `status.json`.

**What if GitHub is down?**
The sync fails, the build unit does not run against a stale checkout, and the
next timer run retries.

**Can it build Darwin configurations?**
No. Darwin needs a macOS builder.

**Why is my machine still building things after adopting?**
See *When adoption does not buy you a cached build* — a non-`success` host, a
local checkout ahead of `source_rev`, or a `nix flake update` after the adoption
all put you back on your own.

## Related

- [nix-serve-ng](https://github.com/aristanetworks/nix-serve-ng)
- [NixOS binary caches](https://nixos.org/manual/nix/stable/package-management/binary-cache.html)
- [SOPS-nix](https://github.com/Mic92/sops-nix)
- [Snowfall Lib](https://snowfall.org/guides/lib/)
