# Omarchy after v4.0.4: what to take into dotnix

Research, 2026-10-16. Recommendation: start with **push-to-talk release
handling, universal copy/paste, and recording lifecycle fixes**. Then consider
opt-in window opacity and reducing idle polling. Keep Noctalia as the desktop
shell. The useful ports are small behaviors expressed in the existing modules.

**Implementation follow-up, 2026-10-16:** items 1–5 are implemented. The
research below records the pre-change state. Dictation and clipboard behaviors
live in the shared Hyprland input helper; terminal classes also seed the opacity
allowlist, including the Quake console. Recording operations are serialized,
status is read-only, and `record-screen watch` uses inotify/pidfds. Noctalia
subscribes to that stream. Clamshell management uses native Hyprland events,
replacing its polling service. The new `desktop-input`, `clamshell`, and
`record-screen` flake checks cover those interfaces; the recording idle guard
traces process creation. Formatting, both Nix linters, the checks, mz/nz builds,
and isolated Hyprland config verification passed. Activation and physical
keyboard/lid/capture checks await an explicitly authorized session test.

## Comparison boundary

- Source repository: `/home/sab/git_priv/omarchy`, remote
  `https://github.com/basecamp/omarchy` (GitHub redirects to `omacom/omarchy`).
- Base: `v4.0.4`, `c668141e9c42b13c80c9ca4ea108e11708c5e8a5`.
- Compared head: `origin/quattro`,
  `51bfd1dbaa1b5f790e19623faf2745945d40c796`, committed October 16 at 05:06
  Moscow time. This is the locally available development snapshot, not a newer
  stable release.
- The checked-out Omarchy `master` is still `f4378f0de` / 3.8.5. All head source
  was read with `git show origin/quattro:<path>`; checkout files were not used
  as the new version.
- The branches diverge: `git rev-list --left-right --count
  v4.0.4...origin/quattro` returns **109 tag-only / 954 head-only** commits.
  Candidates below were checked against `git diff v4.0.4 origin/quattro --
  <path>`; a head-only commit is not by itself evidence of a post-tag feature.
- The net diff is 4,193 files, 421,860 insertions, 10,002 deletions
  (`git diff --shortstat v4.0.4 origin/quattro`). Much of its size is translated
  manuals, themes, and tests, rather than new configuration to transplant.
- Dotnix was inspected from the working tree, initially at
  `dea4e252698ffe16ff88ce95e1bdd6afe43c65a7`. Existing unrelated changes were
  not edited. This investigation changes only this note.

These commands, the pinned source links below, and the linked dotnix files are
the evidence. Proposed benefits and effort are judgments. No live desktop bug
was reproduced, and no configuration was built or activated.

## Ranked shortlist

| Order | Port | Fit | Relative effort |
| --- | --- | --- | --- |
| 1 | Reliable push-to-talk release | Direct match to the current Voxtype binding on mz | Small |
| 2 | Restore universal copy/paste with terminal-aware chords | mz declares the options, but the renderer omits the actions | Small–medium |
| 3 | Serialize recorder operations and fix startup readiness | Existing recorder has concrete lifecycle gaps | Medium |
| 4 | Make window transparency opt-in | Simplifies current global opacity plus exceptions | Small; visible preference change |
| 5 | Apply idle process budgets to custom desktop helpers | nz clamshell and mz recording indicator poll continuously | Medium |
| 6 | Recover fingerprint reader claims after resume | Relevant only to fingerprint-enabled nz | Small, conditional |
| 7 | Per-workspace floating mode | Optional feature for GUI-heavy workspaces | Medium–large |

### 1. Pair dictation press/release actions

Omarchy added `o.bind_hold` in
[54fc12db7](https://github.com/omacom/omarchy/commit/54fc12db76fbb6ed06575ff57839e73c7dbbf817).
Its release half is transparent, ignores modifier changes, and is non-consuming.
A local `held` flag makes the stop action run only after the corresponding
press. This addresses a plain release binding being shadowed when another key
or mouse button is released during the hold. See the
[implementation](https://github.com/omacom/omarchy/blob/51bfd1dbaa1b5f790e19623faf2745945d40c796/default/hypr/helpers.lua#L209)
and its
[behavior checks](https://github.com/omacom/omarchy/blob/51bfd1dbaa1b5f790e19623faf2745945d40c796/test/shell.d/bind-hold-test.sh#L38).

Dotnix still emits two independent bindings, with only `release = true` on the
second, in [Voxtype](/home/sab/dotnix/modules/home/apps/voxtype/default.nix:177).
[mz](/home/sab/dotnix/homes/x86_64-linux/sab@mz/default.nix) uses `ALT + slash`.
This is a strong source-level match to the upstream failure mode, although it
was not reproduced here.

Port the pairing logic into the generated Lua for Voxtype. Keep the current
engine, constrained English/Russian detection, paste output, and key choice.
Acceptance should include releasing Alt first, typing/clicking during a hold,
and releasing slash without a preceding dictation press. Verify these options
against the locked compositor when implementing.

### 2. Finish the universal clipboard bindings

Omarchy changed terminal copy/paste from `Ctrl+Insert` / `Shift+Insert` to
`Ctrl+Shift+C` / `Ctrl+Shift+V`, while GUI windows retain `Ctrl+C` / `Ctrl+V`.
It also added select-all. The changed lines are in
[clipboard.lua](https://github.com/omacom/omarchy/blob/51bfd1dbaa1b5f790e19623faf2745945d40c796/default/hypr/bindings/clipboard.lua#L35).
The explicit key down/up dispatch and terminal classification existed before
the tag; the terminal chords and select-all are the net changes.

There is a more basic dotnix gap: [mz declares copy and paste keys](/home/sab/dotnix/homes/x86_64-linux/sab@mz/default.nix:47),
and the module [declares both options](/home/sab/dotnix/modules/home/desktop/hyprland/default.nix:408),
but [copyPasteBindings](/home/sab/dotnix/modules/home/desktop/hyprland/default.nix:301)
only moves the floating-window shortcut. No copy or paste action is emitted.
This is a statement about the checked-in generator, not the running session.

Implement the advertised Super+C/V behavior using focused-window terminal
classification and the updated terminal chords. The current
[Voxtype option documentation](/home/sab/dotnix/modules/home/apps/voxtype/default.nix)
already explains why Shift+Insert reads the wrong selection in WezTerm.
Preserve dotnix's key choices: Omarchy's Super+X cut binding would conflict
with dotnix's terminal shortcut. Any terminal select-all behavior needs its own
decision; sending Ctrl+A to a shell does not select all terminal text.

### 3. Port recording lifecycle safeguards

Omarchy now has a private runtime/state fallback, serialized start/stop,
cancellation while a start is pending, and readiness failure handling. Inspect
[state paths](https://github.com/omacom/omarchy/blob/51bfd1dbaa1b5f790e19623faf2745945d40c796/bin/omarchy-capture-screenrecording#L40),
[startup](https://github.com/omacom/omarchy/blob/51bfd1dbaa1b5f790e19623faf2745945d40c796/bin/omarchy-capture-screenrecording#L299),
and [locking/cancellation](https://github.com/omacom/omarchy/blob/51bfd1dbaa1b5f790e19623faf2745945d40c796/bin/omarchy-capture-screenrecording#L511).
These are net changes from the tag.

Dotnix already checks its recorder PID/executable, tracks webcam startup,
normalizes audio/video, and produces a thumbnail with a clickable notification.
The remaining gaps in [record-screen](/home/sab/dotnix/packages/record-screen/default.nix) are:

- A fixed `/tmp/record-screen` fallback when the session runtime directory is
  absent. `chmod 700` does not itself establish safe ownership or reject a
  pre-existing symlink. Use a private per-user state fallback.
- No serialization across `start`, `stop`, `toggle`, and status cleanup.
  Two callers can pass the initial inactive check before either publishes its
  PID. Put mutation behind a lock and keep status nonblocking.
- [The five-second startup wait](/home/sab/dotnix/packages/record-screen/default.nix:323)
  checks only process survival after its deadline. A live process that never
  creates its output file is still announced as started. Treat missing output
  as a readiness failure, with separate handling for a portal picker awaiting
  the user.
- The [status command](/home/sab/dotnix/packages/record-screen/default.nix:461)
  performs cleanup. Coordinate it with startup or make observation read-only.

Prioritize those changes over adding another backend. Omarchy also added
`wf-recorder` fallback and parallel thumbnail extraction; dotnix already passes
GPU Screen Recorder's CPU encoding fallback flag. A different capture backend
may help unsupported systems, but there is no demonstrated need on mz in this
investigation. Reuse the upstream concurrency scenarios as acceptance criteria,
adapted to dotnix's commands and dependencies.

### 4. Prefer opt-in application opacity

In [54e3b53b8](https://github.com/omacom/omarchy/commit/54e3b53b88402a4be69f06279e31bf052ceb30c4),
Omarchy removed the global default-opacity tag. Its
[current rules](https://github.com/omacom/omarchy/blob/51bfd1dbaa1b5f790e19623faf2745945d40c796/default/hypr/windows.lua#L18)
make terminals and selected applications transparent explicitly.

Dotnix applies `0.97 0.9` to every window in
[hyprland.lua](/home/sab/dotnix/modules/home/desktop/hyprland/hyprland.lua:203),
then exempts media windows and some helpers. An allowlist would keep browsers,
documents, games, and dialogs opaque without maintaining a growing exception
list. This is a readability preference, not a proven correctness fix.

Expose opacity and matching classes as Nix options, initially opt in terminals,
and keep Noctalia's bar opacity separate. Do not reuse Omarchy's runtime config
rewriting against Home Manager's store-backed files.

### 5. Adopt idle process budgets for the helpers dotnix owns

Omarchy added an idle process-spawn regression guard in `f5006bd41` alongside
event-driven replacements for several periodic probes. Its
[testing notes](https://github.com/omacom/omarchy/blob/51bfd1dbaa1b5f790e19623faf2745945d40c796/docs/testing.md#L87)
describe command-count guards, conditional allowances, and timing budgets.

Two concrete targets in dotnix are:

- [Clamshell management](/home/sab/dotnix/modules/home/desktop/addons/system-polish/default.nix:171)
  runs lid reads, `hyprctl`, and `jq` every second on nz.
- [The recording indicator](/home/sab/dotnix/modules/home/desktop/addons/noctalia/plugins/recording/service.luau:7)
  invokes `record-screen status` every half second even when inactive; that
  command may also perform cleanup.

Use lid/monitor events and recording state notifications or file watches, with
bounded recovery when state becomes uncertain. Retain any poll that has a
measured recovery purpose. Omarchy's own
[monitor watcher](https://github.com/omacom/omarchy/blob/51bfd1dbaa1b5f790e19623faf2745945d40c796/bin/omarchy-hyprland-monitor-watch#L64)
still polls conditionally while docked; event-driven does not mean banning
every timer. The watcher predates v4.0.4; the new performance guard is the main
post-tag practice to borrow.

Measure idle child-process counts before and after, excluding intentional
microphone metering and actual usage refreshes. Keep compositor-dependent
measurements as an explicit session check rather than adding a mandatory live
desktop dependency to headless flake CI. Battery/CPU improvements remain
unmeasured.

### 6. Consider fingerprint recovery on nz

Omarchy added a
[post-resume hook](https://github.com/omacom/omarchy/blob/51bfd1dbaa1b5f790e19623faf2745945d40c796/default/systemd/system-sleep/fprintd-resume#L3)
that queues `systemctl --no-block try-restart fprintd.service` to recover a
wedged reader claim. Only [nz enables fingerprint support](/home/sab/dotnix/systems/x86_64-linux/nz/default.nix:83);
the [fingerprint module](/home/sab/dotnix/modules/nixos/hardware/fingerprint/default.nix:18)
and [sleep hooks](/home/sab/dotnix/modules/nixos/system/sleep/default.nix)
have no corresponding recovery.

Worth adding as a narrowly scoped, optional resume workaround if nz exhibits
reader failures after suspend. Preserve asynchronous restart semantics and
verify repeated suspend/unlock cycles. The NixOS index confirmed
`services.fprintd.enable` and `powerManagement.resumeCommands` on 2026-10-16;
the existing Nix-owned system sleep hook is another integration point. No reader
failure was observed here.

Omarchy's newer fingerprint pause/retry behavior while displays are off lives
inside its QML locker. That needs a separate Noctalia capability investigation;
it is not a shell script to transplant.

### 7. Optional feature: per-workspace floating mode

The dwindle/scrolling cycle existed at v4.0.4. What is new is floating as a third
mode, plus improved persistence/application behavior. The
[toggle](https://github.com/omacom/omarchy/blob/51bfd1dbaa1b5f790e19623faf2745945d40c796/bin/omarchy-hyprland-workspace-layout-toggle#L23)
persists a mode only after runtime application succeeds. The
[mode implementation](https://github.com/omacom/omarchy/blob/51bfd1dbaa1b5f790e19623faf2745945d40c796/default/hypr/workspace-modes.lua#L1)
tags windows it floats so returning to tiling does not retile pre-existing
floating dialogs.

Dotnix currently chooses global dwindle and has per-window floating shortcuts.
A per-workspace option could suit communication or utility windows on mz's
secondary monitor, but that benefit is inferred. Start with explicit workspace
policies and a reversible runtime toggle; choose whether Nix or runtime state
owns each value. The complete upstream feature includes Omarchy shell refreshes
and a titlebar plugin with a fixed `/usr/lib` path. Prototype the behavior
before adding that maintenance burden.

## Defer or skip

- **Replacing Noctalia with Omarchy's Quickshell desktop:** existing dotnix
  [Noctalia integration](/home/sab/dotnix/modules/home/desktop/addons/noctalia/default.nix)
  already owns bar, launcher, notifications, clipboard, wallpaper, lock and
  idle. Most QML changes target that other shell's internals.
- **Omasnap migration and screenshot tooling churn:**
  [dotnix screenshots](/home/sab/dotnix/modules/home/desktop/addons/screenshot/default.nix)
  already cover smart selection, annotation, and English/Russian OCR. The new
  [Super+Shift+S alias](https://github.com/omacom/omarchy/commit/51bfd1dbaa1b5f790e19623faf2745945d40c796)
  is a cheap optional convenience for keyboards without Print.
- **Clipboard open-actions, LocalSend sharing, and terminal cwd inheritance:**
  all existed before v4.0.4. The net terminal change is passing the focused PID
  and avoiding a full process scan in
  [the cwd helper](https://github.com/omacom/omarchy/blob/51bfd1dbaa1b5f790e19623faf2745945d40c796/bin/omarchy-cmd-terminal-cwd#L7).
  Cwd inheritance remains a useful independent idea for dotnix's bare WezTerm
  launcher, but needs a WezTerm-aware design.
- **Chromium direct socket handoff:**
  [the new helper](https://github.com/omacom/omarchy/blob/51bfd1dbaa1b5f790e19623faf2745945d40c796/bin/omarchy-cmd-browser-handoff#L12)
  accepts a narrow list of `/usr/bin` browser executables. Dotnix launches
  Firefox through Nix wrappers, so the implementation does not fit.
- **Multi-subscription account switching:** genuinely new, but conditional on
  needing several accounts for the same provider. Omarchy's
  [agent panel documentation](https://github.com/omacom/omarchy/blob/51bfd1dbaa1b5f790e19623faf2745945d40c796/shell/plugins/agents/README.md#L65)
  describes per-account homes and limits. Dotnix's
  [collector](/home/sab/dotnix/packages/ai-usage/ai_usage.py)
  already handles stale limits and requests Codex limits before optional account
  metadata. Do not import transcript analytics or credential-transfer machinery
  merely to expand an existing quota widget.
- **Cloud dictation:** mz already has local GPU-backed Voxtype with constrained
  English/Russian detection. Backend selection is useful only if local
  transcription quality or speed becomes a problem.
- **Theme intro videos and extra visual effects:** discretionary aesthetics;
  low priority against the concrete interaction fixes above.
- **Arch installers, migrations, Limine/mkinitcpio changes, and hardware fixes
  for N1x/Apple Silicon/ProArt:** tied to a different package/boot model or
  hardware. The Linux hosts in this tree are x86_64; mba13 runs Darwin. No
  evidence here justifies fleet-wide mount-rate or Plymouth console tweaks.

## Implementation order and verification

Make three bounded changes first: dictation hold handling; clipboard binding
generation; recorder lifecycle. Follow with the opacity preference and helper
polling work if desired. Fingerprint recovery and floating workspaces remain
conditional.

For implementation, check generated bindings and exercise the actual edge
cases rather than only matching strings. Recorder checks should cover concurrent
toggles, cancellation in the picker, a live recorder that produces no file,
stale PID state, and an unrelated recorder process. Then run dotnix's formatter,
blocking Nix linters, affected host builds, and shared checks as required by
AGENTS.md. Runtime configuration activation requires the user's explicit
go-ahead. None was performed for this research note.

## Implementation and independent validation — 2026-10-16

Items 1–5 are implemented: paired dictation release handling, terminal-aware
clipboard bindings, serialized/cancellable recorder startup with private state,
terminal-scoped opacity, and event-driven clamshell/recording indicators.
The checks exercise input callbacks, lid/output events, and eight recorder CLI
scenarios, including idle subprocess tracing and simulated PID reuse.

The user requested two external reviewers. Both inspected the same immutable
working-patch snapshot atop `74fe87048ab3cf9a84ec6c8ebdcb0b421475d092` in separate
detached worktrees. Neither changed its source snapshot.

| Review | Model and route | Result |
| --- | --- | --- |
| Recorder correctness/concurrency | `hhdev-glm5-fp8/zai-org/GLM-5.3-Flash`, OpenCode | Approved with two optional follow-ups. Session `ses_ebc4aae1affeVOcp5ZwGGE4Uiw`; final command exited 0. |
| Specification/integration/platform | `gemini-3.8-flash-high`, `agy` through its configured corporate proxy | Conditional pass with findings verified below. Session `41eaba55-1ed6-4e18-b5d6-a8534d1cb734`; status `SUCCESS`, exit 0. |

Parent verification accepted and fixed four findings:

- Normal recorder shutdown used raw PID-existence checks during its timeout.
  It now checks the recorder executable before signaling and throughout the
  wait. A deterministic regression simulating reuse by another executable
  failed before the fix and passes afterward. This reduces PID-reuse risk;
  it does not provide atomic process identity or distinguish reuse by another
  process running the same executable.
- Clamshell `scale = "auto"` was emitted as the undeclared Lua identifier
  `auto`, silently losing the requested setting. Scale is now quoted as a
  string, which the locked Hyprland monitor parser accepts. A generated-config
  callback reproduction failed before the fix and passes afterward.
- Initial lid-state casing is normalized again. The behavioral test uses
  `Open` and failed before the fix.
- Enabling copy/paste on the clipboard-history key now produces an actionable
  Home Manager assertion instead of competing bindings. A configuration with
  copy `C` and default history `C` previously evaluated successfully; it now
  fails with the intended assertion. Existing mz/nz settings build unchanged.

Gemini's serious timer-API finding was dismissed: the locked Hyprland 0.55.4
source registers `hl.timer` and accepts exactly the callback plus
`{ timeout = 50, type = "oneshot" }` used here
(`src/config/lua/bindings/LuaBindingsToplevel.cpp:367–441`). Its excerpt was
incomplete. The proposed replacement with `send_shortcut` was not applied.
Rapid focus changes during the synthetic key's 50 ms interval remain a live
session test, rather than a demonstrated defect from either review.

Across the review axes, correctness and specification have no confirmed
unresolved blockers after these fixes. Module/platform conventions pass the
checks below. Scoped process-ownership checks improved; the reviewers did not
perform a separate comprehensive security audit. The parent reviewed the
post-review delta; the external models reviewed the original snapshot.

Verification after fixes:

- `nix fmt`, `statix check .`,
  `deadnix --fail --no-lambda-pattern-names -- .`, and `git diff --check`: pass.
- `nix flake check`: pass on x86_64-linux, including the three new checks.
  Other architectures are omitted by the standard platform filter.
- `mz` and `nz` system toplevel builds: pass.
- Generated mz/nz configurations with locked Hyprland `--verify-config`: pass
  under isolated home/runtime directories; no session reload was performed.
- The earlier implementation validation also evaluated the Darwin host and
  Linux-only check's Darwin stub derivation paths.

Optional follow-ups retained from GLM: the mutation lock deliberately spans
video finalization, so queued commands can wait and a queued toggle can start
another recording after stop; and webcam preview deserves a dedicated
lock-release regression even though its spawn closes the lock descriptor.
Manual removal of the recorder state directory can terminate its watcher.
Physical keyboard, lid/resume, and actual capture hardware remain untested.
No switch, test activation, deploy, commit, or push was performed.

Raw reviews, briefs, the snapshot manifest/diff, and validation logs are saved
in `/tmp/dotnix-omarchy-review-7ilm5tvi/`. The disposable reviewer worktrees
were removed after checking their source hashes and preserving the artifacts.
