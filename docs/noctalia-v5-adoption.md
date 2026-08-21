# noctalia v5 — what is worth adopting

Research note, 2026-08-20. Scope: the unused surface of noctalia-shell v5 as it
applies to `modules/home/desktop/addons/noctalia/default.nix` on host `mz`.

Every claim below is either a source citation or a command that was run on this
machine. Source citations are against the upstream tree at
`02286bbdcfa81dc3675c9de1d7203a466fcaf0eb` (`origin/main`, 2026-08-19); the flake
input is locked at `b38bf2dde1195e459b4b2a436bde970001d5d5ce` (2026-08-18), five
commits behind. `git diff --stat LOCKED..MAIN -- nix/` is empty and
`src/scripting/plugin_api.h` is byte-identical between the two, so nothing here
depends on bumping the input. `origin/cachix` and `origin/main` are the same
commit — cachix is not a separate branch.

The installed binary reports `5.0.0`; the newest upstream *release tag* is
`v5.0.0-beta.8` (2026-08-10). There is no `v5.0.0` tag.

## The constraint everything else is subject to

`~/.local/state/noctalia/settings.toml` deep-merges *over* the Nix-written
`~/.config/noctalia/config.toml`. The split and the activation-time prune are
documented in `AGENTS.md`; what matters for this note is that **`[theme]` is
GUI-owned**, and `[theme.templates]` is a subtable of it.

Today that is survivable: the sidecar's `[theme]` holds five keys
(`builtin`, `community_palette`, `mode`, `source`, `wallpaper_scheme`) and no
`templates` subtable, so a Nix-declared `[theme.templates]` is live. **One
template toggle in the settings GUI creates that subtable and shadows the Nix
value permanently.** Anything in section 3 below is therefore conditional on
either extending the prune to cover `theme.templates`, or never touching
templates in the GUI.

Arrays are also replaced wholesale rather than merged
(`src/config/config_service.cpp:1346-1368`, comment: *"Tables-over-non-tables,
non-tables, and arrays: overlay replaces base wholesale"*). The one exception is
`session.actions`, merged by identity via `mergeSessionActions` (`:1351-1359`).
The same wholesale-replacement rule is what makes the newly-declared
`control_center.shortcuts` work: `config_service.cpp:1691` seeds the defaults
only when the TOML declares no explicit array.

## 1. Corrections to the current config

**`shell.shared_gl_context = true` is a no-op.** `config_types.h:1100` is
`bool sharedGlContext = true;` — that is already the default. Harmless, but it is
not the NVIDIA workaround it reads as. *(Adopted 2026-08-21: the key was dropped
from the module; a comment records `false` as the escape hatch for
noctalia#3926.)*

**The declared `[[plugins.source]]` has silently dropped both plugin catalogs.**
`config_service.cpp:1694` seeds defaults only when the TOML declares no explicit
array, and `config_types.cpp:59-68` returns two git sources — `official` →
`noctalia-dev/official-plugins`, `community` → `noctalia-dev/community-plugins`.
The single `kind = "path"` source replaces both, so the plugin browser is empty.
This may be the intent of a hermetic Nix-built plugin dir with
`auto_update = "none"`; it is recorded here because it is not written down
anywhere as deliberate. *(Adopted 2026-08-21: now documented as deliberate in a
comment on `plugins.source` in the module.)*

**The sidecar's `wallpaper_scheme = "vibrant"` is a GUI choice, not the default.**
`config_types.h:1510` defaults to `m3-content`. `vibrant` is one of five custom
HSL-space schemes (`vibrant`, `faithful`, `soft`, `dysfunctional`, `muted`) as
opposed to the five Material ones (`m3-tonal-spot`, `m3-content`,
`m3-fruit-salad`, `m3-rainbow`, `m3-monochrome`) — `src/theme/scheme.h:1-70`.
Unknown values fall back to `m3-content` with a warning
(`theme_service.cpp:410`).

## 2. The 47 community-template directories are not half-installed

    $ ls ~/.local/state/noctalia/community-templates/{opencode,zellij,yazi,bat,lazygit}
    template.toml   (each, and nothing else)

`src/theme/community_templates.cpp`: `syncCatalogManifests` downloads only
`template.toml` for ids *not* in `community_ids`; `syncSelectedFromCatalog`
fetches the full file set only for selected ids. The 47 directories are
manifest-only stubs. Nothing is broken and nothing is executing.

They were, however, being re-synced on every start — the catalog fetch is gated
on `enable_community_templates` alone and not on `community_ids` being empty
(`community_templates.cpp:671`, called from `application_services.cpp:536-541` at
start and on every theme reload). That flag is now `false`.

## 3. Templates: what is safe to enable here, measured

The template engine itself fails safe. `template_engine.cpp` `renderFile` (~651)
skips when the rendered text equals the previous content, and on a write failure
logs `failed to open template output {}` and returns. It will not clobber a store
path and will not replace a symlink.

The hazard is entirely in the `post_hook` scripts. Measured on this host:

    $ stat -L -c '%A %U:%G %n' ~/.config/bat/config ~/.config/yazi/theme.toml
    -r--r--r-- root:root /home/sab/.config/bat/config
    -r--r--r-- root:root /home/sab/.config/yazi/theme.toml

    $ touch ~/.config/bat/config
    touch: cannot touch '/home/sab/.config/bat/config': Permission denied

    $ echo x >> ~/.config/yazi/theme.toml
    Read-only file system

Three classes follow from that:

**Destructive — never enable `gtk3` or `gtk4`.**
`assets/templates/gtk/apply.sh:44-49` deletes the home-manager symlink by
design, and names this platform in the comment:

```bash
if [ -w "$resolved" ]; then target="$resolved"
else
    # Read-only symlink (e.g. NixOS): convert to a local file
    rm "$gtk_css"
fi
```

Currently moot — `~/.config/gtk-3.0/gtk.css` and `gtk-4.0/gtk.css` do not exist
and `builtin_ids` is empty. Also note `gtk/` ships no `undo.sh`, so the
per-start undo sweep (below) never reaches it. The hazard only materialises on
enabling the id. Upstream issue #2299; the mitigation named in that thread is
`xdg.configFile."…".force = true`.

**Fails loudly but harmlessly** — scripts that write through the symlink under
`set -euo pipefail`: `bat`, `yazi`, `lazygit`, `ghostty`, `hyprland`.

**Safe — no `apply.sh` at all**: `opencode`, `zellij`, `vscode`, `zed`. Plus
builtins whose only action is a file write into a themes directory: `qt`, `btop`,
`cava`, `helix`, `alacritty`, `kitty`, `wezterm`, `foot`.

### The pre-declare trick, and where it does not work

Most guarded scripts end with a `cmp -s` that skips the write when the target
already contains what would have been written — so pre-declaring the include
line in the home-manager-generated file makes the hook a verified no-op.

`yazi/apply.sh` ends:

```bash
if ! cmp -s "$config_file" "$tmp_file"; then
    cat "$tmp_file" >"$config_file"
fi
```

Our `~/.config/yazi/theme.toml` has **no `[flavor]` section**, so the awk pass
would produce a different file, `cmp` would differ, and the write would fail as
measured above. Adding

```toml
[flavor]
dark = "noctalia"
light = "noctalia"
```

to the home-manager-generated `theme.toml` makes awk's output byte-identical to
its input, `cmp -s` match, and the hook exit 0. The match must be byte-for-byte —
yazi's awk emits unindented keys.

`bat` is the exception: `apply.sh:11` is `touch "$config_file" "$theme_file"`,
before any guard, and that is the call measured failing above. No pre-declaration
helps. Use a user template instead (below) plus
`programs.bat.config.theme = "noctalia"` and an own `bat cache --build`.

`lazygit` and `ghostty` have no config in this repo and no directory on disk, so
they are clean wins as-is. For `hyprland`, `apply.sh` greps for
`require("noctalia")` before appending — adding that line to the existing
`extraConfig` (the module already uses `configType = "lua"`) makes the hook a
no-op.

### The escape hatch: `[theme.templates.user.<id>]`

Not in the earlier inventory of the config surface, and the better route for
anything with a hostile `apply.sh`. `userTemplateSchema()`
(`src/config/schema/config_schema.cpp:1073`, wired at `:1180`) accepts
`enabled`, `input_path`, `input_path_modes.{dark,light}`, `output_path` (string
or list), `output_path_dynamic`, `compare_to`, `colors_to_compare`, `pre_hook`,
`post_hook`, `post_action`, `index`.

`input_path` resolves relative to the config file's parent directory
(`template_engine.cpp:1385`), and `~/.config/noctalia/` is a real home-manager
directory — so inputs can ship as
`xdg.configFile."noctalia/templates/<x>.tmpl".source` and be referenced as
`input_path = "templates/<x>.tmpl"`. Fully Nix-owned, no HTTP, no vendored
`apply.sh`. Community template inputs to copy in live at
`https://api.noctalia.dev/templates/<id>/<file>`.

Template language: `{{ expr }}`; `<* for *>` / `<* if *>` blocks; colours as
`{{ colors.<name>.<mode>.<format> }}` with modes `dark|light|default` and formats
`hex hex_stripped rgb rgb_csv rgba hsl hsla`; tonal access as
`{{ palettes.<family>.<tone>.<format> }}`. Full token list in
`src/theme/tokens.h` — 50 M3 roles plus 22 `terminal_*`. Hook commands are
themselves rendered through the engine, with `{{ mode }}`, `{{ image }}`,
`{{ config_dir }}` available. Offline authoring: `noctalia theme --scheme <name>
--dark|--light|--both -o <f> -r <in:out>`.

### The undo sweep is unavoidable

`template_apply_service.cpp` sets `reconcileDisabledBuiltinIds` whenever
`m_lastAppliedRequest` is empty, so once per process start
`undoDisabledBuiltinTemplates` runs the `undo_hook` of every builtin absent from
`builtin_ids`. Nineteen builtins ship one:

    alacritty btop cava emacs foot ghostty helix hyprland kde kitty labwc
    mango niri qt scroll starship sway umbriel wezterm

`enable_builtin_templates = false` only empties the enabled set; the sweep still
covers everything. This is the source of the recurring
`touch: cannot touch '~/.config/wezterm/wezterm.lua': Permission denied`. There
is no config lever. Enabling an id makes it *apply* to the same read-only path
instead, which is worse.

## 4. Palettes

`programs.noctalia.customPalettes.<name>` is a drop-in, store-backed replacement
for the community fetch. The home-manager module writes
`~/.config/noctalia/palettes/<name>.json` (`nix/home-module.nix:128-137`) and
noctalia reads exactly that path (`custom_palettes.cpp:215-221`:
`customPaletteDir() = configDir()/"palettes"`). Select it with
`theme.source = "custom"` and `theme.custom_palette = "<name>"`; the format is
the same as a community palette (`theme_service.cpp:462-470`). Vendoring
`Oxocarbon` this way removes the `api.noctalia.dev` dependency and gains a
restart trigger, since the module lists every palette store path in
`X-Restart-Triggers`.

Caveat: that JSON carries only 16 roles per mode (`src/theme/fixed_palette.h`)
plus a nested `terminal` block — far less than the ~50-token M3 set a
wallpaper-derived palette exposes. `theme.source` is `wallpaper` here, which is
the good case; switching to `custom` would starve any template referencing e.g.
`surface_container_high`.

Ten builtin palettes (`builtin_palettes.cpp`): Ayu, Catppuccin, Dracula,
Eldritch, Gruvbox, Kanagawa, Noctalia, Nord, Rosé Pine, Tokyo-Night.

## 5. Hooks

All 18 arrays are empty today. Keys, in enum order
(`config_types.h:1349-1392`): `started`, `wallpaper_changed`, `colors_changed`,
`theme_mode_changed`, `session_locked`, `session_unlocked`, `logging_out`,
`rebooting`, `shutting_down`, `wifi_enabled`, `wifi_disabled`,
`bluetooth_enabled`, `bluetooth_disabled`, `battery_charging`,
`battery_discharging`, `battery_plugged`, `battery_percentage_changed`,
`power_profile_changed`.

Three facts to design around:

- **Commands run under `/bin/sh -lc`** — a *login* shell, and not fish
  (`src/core/process/process.cpp:837`, `:844`, `:957`). Write POSIX sh.
- **Only four events set environment variables.** `wallpaper_changed` →
  `NOCTALIA_WALLPAPER_PATH` / `_CONNECTOR` (and it fires once per changed
  output — relevant with two monitors); `theme_mode_changed`,
  `power_profile_changed`, `battery_percentage_changed`. The other fourteen,
  including `colors_changed`, get nothing and must read state themselves.
- **`colors_changed` over-fires.** Upstream #3814: still reproducible on
  beta.8 — "simply changing the interface scale/size is enough". It also fires
  *after* templates are applied (`application_services.cpp:652`). Prefer
  `wallpaper_changed`; any `colors_changed` hook must be idempotent and cheap.

`logging_out`, `rebooting` and `shutting_down` fire *blocking*
(`application_ui.cpp:374-376`) and can delay the session action. Everything else
is fire-and-forget with stdio discarded, so a hook cannot report failure — it
must self-log.

Upstream docs are not a source here: `docs.noctalia.dev/…/configuration/hooks/`
is HTTP 404 and the IPC page documents no environment variables.

## 6. Cheap wins not yet taken

**`custom_button` bar widgets.** A real widget type
(`src/shell/bar/widgets/custom_button_widget_definition.cpp`) taking `glyph`
(a Tabler icon name or curated alias, `glyph_registry.cpp`), `label`, `tooltip`
and `custom_image`. ~~`command`~~ — correction: the `command`/`left_command`
keys are v4 leftovers, auto-migrated away (`config_migrations.cpp:279-329`);
clicks live in the shared `[widget.<name>.actions]` gesture table (`left`,
`right`, `middle`, `back`, `forward`, `scroll_*`) whose values are **bare IPC
verbs** (`left = "wallpaper-random"`), `exec <cmd>`, or `none`. Verbs are
resolved at bind time, not by `noctalia config validate` — a typo is a runtime
log line only. Turns any unbound IPC verb — `theme-mode-toggle`,
`templates-apply`, `wallpaper-random`, `panel-toggle launcher`,
`effects-profile-set`, `taskbar-cycle` — into a bar button in Nix, with no
plugin. Highest capability per line on this list. *(Adopted 2026-08-21: a
`wallpaper-shuffle` button (left `wallpaper-random`, right
`panel-toggle wallpaper`) plus the builtin `theme_mode` widget — whose
left-click already defaults to `theme-mode-toggle`, so no custom_button was
needed for it — joined the end lane in
`modules/home/desktop/addons/noctalia/default.nix`.)*

**`[system.monitor]` poll intervals.** `config_types.h:1163-1200`:
`kDisabledPollSeconds = 0.0F`, non-zero values clamped to `[1, 120]`, comment
*"A poll value of 0 disables that metric entirely (no sampling, no wakeups)"*.
Defaults are cpu 2 / memory 2 / gpu 5 / network 3 / disk 10. GPU probes only run
while something displays a GPU stat, so an idle machine does not wake the dGPU —
but see #3603. ~~Pin `cpu_temp_sensor_path` rather than letting it probe.~~
Correction: **do not pin it on this host.** A pinned value must be a literal,
existing `temp*_input` file (`cpu_temp_sensor.cpp`, `readConfiguredSensor` —
no globbing, silent fallback to autodetect when absent), and the hwmon index is
not boot-stable on mz: k10temp was `hwmon4` when the waybar config was written,
`hwmon2` on 2026-08-21. Autodetect ranks by *driver name* — k10temp/Tctl gets
`knownDriverPriority` 0 — so the probe deterministically lands on the right
sensor every boot; the per-poll scan is a handful of sysfs reads every cpu poll.
(The same instability means waybar's hard-coded `hwmon4/temp1_input` path is
stale.) *(Adopted 2026-08-21: `gpu_poll_seconds = 0` and `disk_poll_seconds = 0`
seeded in the module; cpu/memory/network left at defaults, sensor path left on
autodetect.)*

**Hyprland layer rules for noctalia surfaces.** With
`bar.main.background_opacity = 0.29`, `blur` plus `ignore_alpha 0.5` on
namespace `^noctalia-(bar-.+|notification|dock|panel|attached-panel|osd)$` is the
difference between transparent and frosted; `no_anim` removes Hyprland's layer
animation from every panel. There is a separate `^noctalia-backdrop` namespace.
*(Adopted 2026-08-21: both rules added to
`modules/home/desktop/hyprland/hyprland.lua`.)*

**Derive `capsule_group` from the widget lists.** The two groups
(`group:stats`, `group:net`) are currently declared in two places; filtering
`group:`-prefixed entries out of the start/center/end lists and mapping them to
group definitions removes that drift class. The same shape generalises to
per-monitor bars, which matters given DP-1 3840×2560 against HDMI-A-1 1080p.
*(Adopted 2026-08-21, inverted: groups are declared once in a `capsuleGroups`
attrset; `capsule_group` is mapped from it and lanes reference groups through
`groupToken`, which `assert`s the id exists — a renamed group now fails at eval
instead of silently unboxing.)*

**Config-directory layering.** Every `*.toml` directly in `~/.config/noctalia/`
is a root, merged in filename sort order with later files winning
(`config_service.cpp:381`, `config_merge.cpp`). The home-manager module only ever
writes `config.toml` (`nix/home-module.nix:118`), so a plain
`xdg.configFile."noctalia/zz-mz.toml"` is a host override with no `mkMerge`.
`[include].files` pulls in more, with the including file winning
(`config_merge.cpp:124-127`), and `[include].autoload = false` in any root turns
the directory opt-in — a profile switch, which fits the `colorSource` A/B.

**`wallpaper.transition` defaults to all six** (`fade wipe disc stripes zoom
honeycomb`, one picked per change) at `transition_duration = 1500`. Correction:
the keys are `transition` (singular, array of enums) and `transition_duration`
(no `_ms`; float ms, range [100, 30000]) — `config_schema.cpp:1591-1594`.
Narrowing to `["fade"]` is worth it on the 3840×2560 output. *(Adopted
2026-08-21: seeded in the module's `wallpaper` table; live because the sidecar
carries no `transition` key today — wallpaper.* stays GUI-owned, no prune
change.)*

## 7. Plugins

`kOldestSupportedPluginApiVersion = 3`, `kCurrentPluginApiVersion = 28`
(`plugin_api.h:7,30-31`, identical at both revisions). The highest api in the
community catalog is 26, so **every catalog plugin installs at the locked rev** —
reaching them only requires re-declaring a git source (section 1).

Twelve official plugins; 109 community. Ones matching this stack:
`avivbintangaringga/nix-monitor` (api 3, nixpkgs update monitor),
`weinguyen/opencode-companion` (21), `davemhammer/obsidian` (10, vault git
status), `davemhammer/k8s-status` (10), `nomadcxx/gamer-mode` (19),
`blackbartblues/keymap` (9, Hyprland keybinds), `tphilippot/git_companion` (23).
The fully-Nix alternative is vendoring them into the existing `path` source.

Note for `mic_vu`: `PluginSourceKind::Path` is documented as *"an immutable local
directory (e.g. a Nix store path) the host treats read-only (update/auto-update/
remove are no-ops)"*, so the current arrangement is the intended one. The Luau
API's `noctalia.getSetting(path)` (api ≥ 26) can read any effective config value
by dotted path, which would let the plugins read theme colours instead of
hard-coding hues — but the locked rev supports it, and `getConfig` is what the
plugins use today.

## 8. The home-manager module has exactly six options

`nix/home-module.nix` (148 lines, identical at both revisions):
`enable`, `systemd.enable`, `package`, `validateConfig`, `settings`,
`customPalettes`. **There is no option for templates, plugins, greeter, or
firefox-theme** — all of it goes through `settings`, which accepts an attrset, a
raw TOML string, or a path.

Two consequences:

- `validateConfig = true` runs `noctalia config validate` against the generated
  file only. Upstream documents that command as validating one file *"without
  scanning default locations or merging settings.toml"* — so it structurally
  cannot catch sidecar schema rot. Validating the *merged* config is a separate,
  manual step per version bump.
- The unit's `X-Restart-Triggers` covers config.toml plus every palette store
  path, and `Restart = "on-failure"`. The `StartLimitIntervalSec = 0` /
  `RestartSec = 2` hardening in this repo is genuinely additive.

Debug environment variables in source: `NOCTALIA_CONFIG_HOME`,
`NOCTALIA_STATE_HOME`, `NOCTALIA_DATA_HOME`, `NOCTALIA_LOG_LEVEL`,
`NOCTALIA_PROFILE`, `NOCTALIA_IDLE_PROFILE`, `NOCTALIA_BLUR_TRACE`,
`NOCTALIA_GAMMA_PROFILE`, `NOCTALIA_SPECTRUM_DEBUG`, `NOCTALIA_SCREENSHOT_PATH`.
The first three redirect each layer independently — the documented way to test a
bar layout against a throwaway profile without risking the live sidecar.

## 9. Open upstream issues that bear on this host

- **#3613** lockscreen high GPU load — noctalia is the only locker here, so
  leave `lockscreen.blurred_desktop` off.
- **#3814** `colors_changed` over-fires (see section 5).
- **#3603** sysmon keeps the NVIDIA dGPU awake.
- **#3086** crash with high-resolution wallpapers while modifying settings —
  DP-1 is 3840×2560.
- **#3523** memory growth with the audio visualiser — adjacent to `mic_vu`.
- **#3796** bar effect opacity also affects panel opacity — this host runs 0.29.
- **#1987** lockscreen solid orange/red after DPMS off on NVIDIA.
- **#3890** freeze switching workspaces from a fullscreen game.
- **#3101** starship `apply.sh` replaces the symlink; **#2299** the same for gtk.
- **#3770** tracks nix/home-manager plugin packaging.

## 10. Unverified

- Whether `~` expands in `input_path` at 5.0.0. `resolveConfigPath` does call
  `expandUserPath`, but open #3039 requests exactly this. Prefer relative paths.
- The `fireWithEnv` implementation does `::setenv` / `::unsetenv` around a
  fire-and-forget async hook, which is process-global rather than per-command —
  a latent race between concurrently-fired hooks. Not reproduced.
- Community palettes have no per-palette pin or version mechanism anywhere in
  the source. This is absence of evidence, not evidence of absence; vendoring via
  `customPalettes` sidesteps the question.
- The 248 `loaded plugin 'sab/mic_vu'` lines in the current boot are a
  config-reload storm, not a per-start count: each reload re-registers all
  plugins three times (visible as three pairs between consecutive
  `[config] 1 bar(s) defined` lines), and reloads arrive in bursts when the
  config.toml symlink is swapped during a rebuild. INF-only, no config lever
  found, functionally harmless.
