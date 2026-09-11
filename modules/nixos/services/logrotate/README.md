# logrotate — one rule per application

`custom.services.logrotate.rules.<name>` renders one logrotate block per
application, each with its own `su` line. It replaces the single shared
`multiple_paths` rule that `logFiles` used to build.

## Why the shared rule failed

Every night on zanoza, `logrotate.service` exited non-zero (most recently
**2026-09-10**) with:

```
error: skipping "/tank/sing-box/logs/sing-box.log" because parent directory has
insecure permissions (It's world writable or writable by group which is not
"root") Set "su" directive in config file to tell logrotate which user/group
should be used for rotation.
```

Only sing-box triggers it. `/tank/sing-box/logs` is owned by a container uid and
is group-writable — and the reason it is group-writable is the ACLs: the
`alloy-log-acls` oneshot in `modules/nixos/containers/loki` runs
`setfacl -R -m g:logreaders:rX` on that directory so Alloy can read the logs.
Adding a named ACL entry raises the ACL **mask**, and the mask is what the group
permission bits report — so the directory reads as `0775` with a non-root gid,
even though no real group was granted write access.

logrotate refuses to touch a log whose parent directory is world-writable or
group-writable by a group other than `root`, because rotating there as root is a
privilege-escalation vector: the directory owner could swap a path under
logrotate's feet. The fix it proposes is `su`.

logrotate skips only the offending path: it finishes the remaining patterns in
the shared rule and then exits non-zero. So the other three applications kept
rotating normally throughout — `/tank/authelia/logs/authelia.log-2026-09-11.zst`
and `/tank/traefik/logs/access.log-2026-09-11.zst` were both produced on the
morning of the last failure. The cost was therefore not a stalled rotation but a
unit failing every single day, and one log — `sing-box.log` — growing unbounded
behind it, to 42 MB by the time this was fixed. The daily alert was real and
specific, not noise.

## `su root root`, and why not numeric ids

The four log directories under `/tank` are owned by four different container
uid/gid pairs, so one shared `su` line could never serve them — hence one block
per application. The natural next thought is to give each block the numeric owner
of its directory. **That does not work here.**

These are `nixos-containers` *without* user namespaces: a container's uid 999 is
literally uid 999 on the host, but the *name* is not shared — the container has
its own `/etc/passwd`. logrotate resolves `su` through the name database and then
confirms the id with `getpwuid`/`getgrgid`; a bare number that no account holds is
rejected, not passed through. Verified on zanoza with `logrotate -d -f` as root:

```
error: /tmp/lr.conf:13 unknown user '999'
error: found error in "/tank/authelia/logs/*.log", skipping
error: unknown group '998'
error: found error in "/tank/torrents/log/*.log", skipping
error: unknown group '998'
error: found error in "/tank/sing-box/logs/*.log", skipping
```

`getent passwd 999` and `getent group 998` are empty on zanoza. Three of the four
rules were silently dropped. Only traefik's `su 997 995` survived, and only by
accident — both numbers happen to be held by `systemd-oom`.

So the rules use the default, `su root root`, which processes every pattern with
no permission error at all:

```nix
rules = {
  authelia.files = [ "/tank/authelia/logs/*.log" ];
  sing-box.files = [ "/tank/sing-box/logs/*.log" ];
};
```

What silences the check is the **presence** of the `su` directive, not what it
switches to. Switching to root is a no-op — logrotate already runs as root — so
this is exactly the behaviour of the three rules that have been working all along:
the rotated `.zst` files under `/tank/authelia` and `/tank/traefik` are owned by
the container uids because `copytruncate` preserves the original file's ownership,
not because logrotate dropped privileges.

Set a real `user`/`group` only when the host has a **named** account that owns the
directory — a plain NixOS service log, not a container's. Check first:

```
stat -c '%u:%g %a' /tank/<service>/logs
getent passwd <uid>; getent group <gid>
```

If either `getent` is empty, leave the defaults.

### The trade-off, stated plainly

Rotating as root inside a directory writable by a container's group is precisely
what upstream's check warns about: whoever can write to that directory could, in
principle, race logrotate into touching a path it did not intend.

We accept it. The containers are ours, the directories are service-owned rather
than user-writable, and the group-writable bit is an artifact of the ACL mask we
set ourselves for Alloy. The alternative — inventing host accounts whose only
purpose is to hold uid 999 and uid 998 so `su` can name them — adds a real,
permanent identity to the host to satisfy a check we would then be satisfying
nominally anyway. Revisit this if these containers ever gain user namespaces, at
which point the ids stop being shared and real host accounts become meaningful.

## copytruncate vs. reopen

Every rule defaults to `copytruncate = true`: logrotate copies the log aside and
truncates the original **in place**, keeping the inode.

That matters because Alloy tails these files. A normal rotation renames the log
and creates a new one, leaving Alloy holding a file handle on a file nobody writes
to any more — log shipping silently stops until Alloy rediscovers the target. With
`copytruncate` the inode never changes, so Alloy's tail position survives.

The cost is a small race: lines written between the copy and the truncate are
lost. For these logs that is acceptable.

The alternative is `copytruncate = false` plus a `postrotate` hook that signals the
application to reopen its log:

```nix
traefik = {
  files = [ "/tank/traefik/logs/*.log" ];
  copytruncate = false;
  postrotate = "systemctl kill -s USR1 container@traefik.service";  # not yet used
};
```

The module asserts that `postrotate` is only set with `copytruncate = false`, since
with copytruncate the application never needs to reopen anything and the signal is
pure noise.

Where each application stands today:

| Application | Reopens on a signal? | Mode used |
| ----------- | -------------------- | --------- |
| authelia    | no                   | copytruncate |
| qBittorrent | no                   | copytruncate |
| sing-box    | no                   | copytruncate |
| Traefik     | **yes** (`USR1`)     | copytruncate |

Traefik is the one future candidate for the reopen path — it is also the noisiest
log, so it has the most to gain from losing the copytruncate race window. It runs
inside a container, though, and the exact signal delivery has not been tested, so
it stays on copytruncate until someone can verify a real rotation.

## Alloy compatibility

- **Inode is kept** by `copytruncate`, so Alloy keeps tailing across a rotation.
- **Rotated files are never re-ingested.** They are named
  `<name>.log-YYYY-MM-DD.zst` (`dateext` + `dateformat -%Y-%m-%d` + `compressext
  .zst`), which does not match Alloy's `*.log` globs, so rotated copies are not
  picked up as new targets and lines are not duplicated into Loki.
- **Rotated copies stay readable.** `alloy-log-acls` sets *default* ACLs on the log
  directories, so files created there — including the rotated copies — inherit
  `g:logreaders:r`. (Those same ACLs are what makes the sing-box directory look
  group-writable; see above.)

## Validating a change without rotating anything

Debug mode parses the config, runs the directory-permission check, and decides
what *would* rotate, but changes nothing on disk:

```
sudo logrotate -d -f -s /tmp/logrotate.state /etc/logrotate.conf
```

Use a throwaway state file so the real `/var/lib/logrotate.status` is untouched.
`-f` forces the decision so every rule is considered even when it is not due.

What to look for:

- No `insecure permissions` errors — that is the bug this module exists to fix.
- No `unknown user` / `unknown group` errors — see above; these mean a rule was
  skipped entirely, which looks like success in the exit code.
- `Handling N logs` with N equal to the number of rules plus the NixOS defaults
  (`/var/log/btmp`, `/var/log/wtmp`).

## Running one real rotation

Once the debug output is clean and the owner has approved it:

```
sudo systemctl start logrotate.service
journalctl -u logrotate -n 50
```

Then confirm the result on disk — a fresh `.zst` next to a truncated original:

```
ls -la /tank/sing-box/logs/
```

The first run on sing-box rotates a 42 MB backlog, so it takes noticeably longer
than a steady-state run.

A **second** forced run on the same day prints, per rule:

```
destination /tank/sing-box/logs/sing-box.log-2026-09-11.zst already exists, skipping rotation
```

That is `dateext` doing its job — the rotated name is derived from the date, so
there is only one slot per day. Expected, not an error.
