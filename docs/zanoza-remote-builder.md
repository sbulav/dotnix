# Constrained zanoza remote builder

This runbook covers the remote builder introduced for GitHub issue #29.

`beez` remains the orchestrator, result signer, and binary-cache server.
`zanoza` only executes derivations selected by the Nix scheduler and returns
their store paths to `beez`.

## Safety model

- A dedicated `nix-builder` system user is trusted by the Nix daemon, but has
  no sudo access and cannot log in with an interactive shell through its key.
- The authorized key is restricted to the `nix-daemon --stdio` command, the
  source address of `beez`, and OpenSSH's `restrict` option.
- `beez` pins zanoza's SSH host key instead of accepting it on first use.
- Zanoza's whole Nix daemon cgroup is capped at two concurrent jobs, two cores
  per job, 400% CPU, 8 GiB soft memory pressure, 10 GiB hard memory use, and
  2 GiB swap. CPU and I/O weights are deliberately lower than production
  services.
- `fallback = true` keeps local builds available when zanoza cannot be reached.

The daemon limits also apply to local Nix builds run directly on zanoza. That
is intentional: production services must retain priority regardless of who
started a build.

## Provisioning

Proceed only after the owner confirms the storage-health prerequisite and the
recorded SMART/ZFS baseline has not deteriorated.

1. Generate a dedicated, passphrase-free Ed25519 key on a trusted workstation:

   ```console
   ssh-keygen -t ed25519 -f ./beez-zanoza-builder -N '' -C beez-zanoza-nix-builder
   ```

2. Add the private key as the `nix-remote-builder-ssh-key` value in
   `secrets/beez/default.yaml` using SOPS. Do not commit the plaintext file.

3. Put the contents of `beez-zanoza-builder.pub` in
   `services.nix-remote-builder.server.authorizedKey` on zanoza.

4. On zanoza, verify `/etc/ssh/ssh_host_ed25519_key.pub` through the existing
   trusted administrator connection, then encode the complete public-key line:

   ```console
   base64 -w0 /etc/ssh/ssh_host_ed25519_key.pub
   ```

   Put the result in
   `services.nix-remote-builder.client.publicHostKey` on beez.

5. Enable and deploy the server side on zanoza first. Verify the generated key
   restriction in `/etc/ssh/authorized_keys.d/nix-builder`, then enable and
   deploy the client side on beez. Always request owner approval before either
   switch.

## Verification and benchmark

Confirm the client configuration on beez:

```console
nix config show builders
sudo cat /etc/nix/machines
```

Force a unique smoke derivation to use zanoza by disabling local jobs for this
one command:

```console
sudo nix build --impure --no-link --no-substitute --max-jobs 0 \
  --print-build-logs \
  --expr 'with import <nixpkgs> {}; runCommand "remote-smoke-${builtins.toString builtins.currentTime}" {} "echo remote-ok > $out"'
```

The beez log must identify the `ssh-ng://nix-builder@...` machine. At the same
time, observe zanoza and its production services:

```console
sudo journalctl -fu nix-daemon.service
systemd-cgtop
systemctl show nix-daemon.service \
  -p CPUUsageNSec -p MemoryCurrent -p MemoryPeak -p IOReadBytes -p IOWriteBytes
```

For the representative benchmark, start from the same committed flake revision
and lock file for every run. Record wall time and the monitoring dashboards for:

1. a normal cache build with the remote builder available;
2. a second warm-cache run;
3. a local-only run using the disable file below.

Compare service latency and host CPU, memory, swap, I/O pressure, ZFS health,
and Nix daemon journal entries over the same time window. Stop the test if disk
health changes or critical-service latency materially regresses.

## Fast disable and fallback test

On beez, force scheduled and manual cache-builder runs to stay local without a
NixOS switch:

```console
sudo touch /run/nix-cache-builder-local-only
sudo systemctl stop nix-cache-builder.service
sudo systemctl start nix-cache-builder.service
```

The journal must contain `Remote builders disabled ...; using beez only`, and
the run must finish without any `ssh-ng://` build lines. Re-enable opportunistic
use after the incident or test:

```console
sudo rm /run/nix-cache-builder-local-only
```

The file is under `/run`, so a reboot also clears the emergency override.
For a persistent disable, set
`services.nix-remote-builder.client.enable = false` and rebuild beez after
owner approval.

Relevant logs:

```console
# Orchestration, signing, publication, and chosen builder
sudo journalctl -u nix-cache-builder.service --since today

# Remote daemon connections and builds
sudo journalctl -u nix-daemon.service --since today
```
