{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.desktop.addons.noctalia;

  # Staged takeover of the old seven-tool stack (issue #37). Surfaces the
  # shell does NOT own yet are pinned off here and flipped slice by slice:
  #   slice 1: bar + notifications + OSD   (waybar/mako off)        — done
  #   slice 2: launcher + session/power    (rofi/wlogout off)       — done
  #   slice 3: wallpaper engine + palette  (hyprpaper/waypaper off) — done
  #   slice 4: sysmon widgets + mic VU plugin                       — done
  #   slice 5a: manual lock                (old stack kept as fallback) — done
  #   slice 5b: idle behaviors             (swaylock/hypridle off)  — done

  # Nix-managed plugin source (a read-only "path" source in noctalia terms,
  # scanned one level deep — every child dir is a plugin). plugins/mic_vu/
  # in this repo is a template: the mic source match and the absolute tool
  # paths are baked in here so the runtime needs nothing from home.packages
  # and survives PATH-less systemd activation. plugins/sysmon/ ships as-is.
  # @SOURCE_MATCH@ lands inside a Luau double-quoted string, so it gets Luau
  # string escaping (backslashes and quotes) — escapeShellArg alone only
  # protects the substituteInPlace command line, not the target syntax. A
  # regex like AKG\.C44 would otherwise parse as a bad escape sequence.
  luauSourceMatch = escape [ "\\" "\"" ] cfg.micVuMeter.sourceMatch;
  pluginSource = pkgs.runCommand "noctalia-plugins-dotnix" { } ''
    mkdir -p $out
    cp -r ${./plugins/mic_vu} $out/mic_vu
    cp -r ${./plugins/sysmon} $out/sysmon
    chmod -R u+w $out
    substituteInPlace $out/mic_vu/plugin.toml \
      --replace-fail '@MIC_CTL@' '${micCtl}/bin/akg-mic-ctl' \
      --replace-fail '@PAVUCONTROL@' '${pkgs.pavucontrol}/bin/pavucontrol'
    substituteInPlace $out/mic_vu/service.luau \
      --replace-fail '@SOURCE_MATCH@' ${escapeShellArg luauSourceMatch} \
      --replace-fail '@PW_CAT@' '${pkgs.pipewire}/bin/pw-cat' \
      --replace-fail '@PACTL@' '${pkgs.pulseaudio}/bin/pactl' \
      --replace-fail '@OD@' '${pkgs.coreutils}/bin/od' \
      --replace-fail '@GAWK@' '${pkgs.gawk}/bin/gawk'
  '';

  # Port of the old waybar akg-mic-ctl: mute toggle / 5% gain steps with a
  # replaceable notification. Unlike the waybar copy (wpctl on
  # @DEFAULT_AUDIO_SOURCE@) this acts on the source the meter matches, so
  # click-to-mute always hits the mic the needle is showing.
  micCtl = pkgs.writeShellApplication {
    name = "akg-mic-ctl";
    runtimeInputs = with pkgs; [
      pulseaudio
      libnotify
      gawk
      coreutils
      util-linux # flock
    ];
    text = ''
      set -uo pipefail

      action="''${1:-status}"
      timeout=1500
      # noctalia's daemon only implements replaces_id (no synchronous hint
      # like mako), so keep the printed notification id around and replace
      # the previous toast instead of stacking one per scroll notch.
      idfile="''${XDG_RUNTIME_DIR:-/tmp}/akg-mic-ctl.notify-id"

      # A fast scroll fires several instances at once; unserialized they race
      # the id file (each reads the pre-burst id, so toasts stack anyway) and
      # interleave their pactl steps. First-come order, cheap to hold.
      exec 9> "$idfile.lock"
      flock -w 2 9 || true

      notify_toast() {
        local title="$1" body="$2" icon="$3" prev
        local -a args
        prev=$(cat "$idfile" 2>/dev/null || true)
        args=(-t "$timeout" -i "$icon" -p)
        if [[ -n "$prev" ]]; then args+=(-r "$prev"); fi
        notify-send "''${args[@]}" "$title" "$body" > "$idfile" || true
      }

      # writeShellApplication runs under errexit: every pactl that may fail
      # (mic unplugged) needs an explicit fallback or the click dies silently.
      #
      # Match the node-name column only, and never a monitor source. A USB mic
      # contributes BOTH an alsa_input.* and an alsa_output.*.monitor node, and
      # the monitor sorts first, so matching a bare substring against the whole
      # line ($0) resolves "AKG_C44" to the playback loopback — every
      # set-source-mute/set-source-volume below then lands on the wrong node
      # while the needle keeps working (PipeWire re-routes pw-cat's --target).
      src=$(pactl list sources short 2>/dev/null \
        | gawk -v m=${escapeShellArg cfg.micVuMeter.sourceMatch} \
            '$2 !~ /[.]monitor$/ && $2 ~ m { print $2; exit }' \
        || true)
      # No fallback to the default source: the meter face shows "no mic", so
      # a click must not mute or regain whatever other source happens to be
      # the default (webcam mic). Say so and stop.
      if [ -z "$src" ]; then
        notify_toast "🎤 Mic not found" \
          "no source matches ${cfg.micVuMeter.sourceMatch}" \
          "microphone-sensitivity-muted"
        exit 0
      fi

      # Mutations race hot-unplug; on failure surface the loss instead of
      # letting errexit kill the click silently.
      mutate() {
        if ! pactl "$@" 2>/dev/null; then
          notify_toast "🎤 Mic lost" "$src vanished mid-action" \
            "microphone-sensitivity-muted"
          exit 0
        fi
      }

      read_state() {
        local vol muted
        vol=$(pactl get-source-volume "$src" 2>/dev/null \
          | gawk -F/ 'NR == 1 { gsub(/[ %]/, "", $2); print $2; exit }' \
          || true)
        case "$(pactl get-source-mute "$src" 2>/dev/null || true)" in
          *yes*) muted=1 ;;
          *) muted=0 ;;
        esac
        printf '%s %s\n' "''${vol:-0}" "$muted"
      }

      notify_state() {
        local vol muted
        read -r vol muted < <(read_state)
        if [[ "$muted" == "1" ]]; then
          notify_toast "🎤 Mic muted" "gain ''${vol}% (no signal)" \
            "microphone-sensitivity-muted"
        else
          notify_toast "🎤 Mic active" "gain ''${vol}%" \
            "microphone-sensitivity-high"
        fi
      }

      case "$action" in
        mute)
          mutate set-source-mute "$src" toggle
          notify_state
          ;;
        vol-up)
          mutate set-source-volume "$src" +5%
          read -r vol _ < <(read_state)
          if [ "''${vol:-0}" -gt 100 ]; then
            mutate set-source-volume "$src" 100%
          fi
          notify_state
          ;;
        vol-down)
          mutate set-source-volume "$src" -5%
          notify_state
          ;;
        status)
          notify_state
          ;;
        *)
          echo "usage: $0 {mute|vol-up|vol-down|status}" >&2
          exit 2
          ;;
      esac
    '';
  };

  c = config.custom.theme.colors;
  hex = name: "#${c.${name}}";

  wallpaperMode = cfg.colorSource == "wallpaper";

  # Per-widget accents. In "theme" mode every module gets its own vu-neon
  # hue as a literal, exactly like the old waybar CSS (#workspaces mint,
  # #cpu cyan, #memory pink, …). In "wallpaper" mode literals would fight
  # the derived palette, and M3 only exposes three accent roles plus error —
  # so there the accent moves from the widget to the capsule group below and
  # only the two widgets that sit outside a group keep an individual role.
  widgetAccents =
    if wallpaperMode then
      {
        keyboard_layout.color = "tertiary";
        session.color = "error";
      }
    else
      {
        keyboard_layout.color = hex "mint";
        sysmon-cpu.color = hex "cyan";
        sysmon-ram.color = hex "pink";
        sysmon-temp.color = hex "amber";
        bluetooth.color = hex "cyan";
        network.color = hex "blue";
        session.color = hex "pink";
      };

  # The group box itself: a hairline outline around a fully transparent fill
  # (bar.cpp applies capsule opacity to the fill only, border is drawn
  # independently) — the waybar `group/stats` and `group/network` boxes.
  groupBorder = if wallpaperMode then "outline" else hex "separator";

  mkCapsuleGroup =
    id: foreground: members:
    {
      inherit id members;
      opacity = 0.0;
      radius = 8.0;
      padding = 6;
      widget_spacing = 6;
      border = groupBorder;
    }
    // optionalAttrs wallpaperMode { inherit foreground; };

  # Single source of truth for the boxed widget sets: capsule_group is derived
  # from this attrset and the lanes reference it through groupToken, so a
  # renamed or removed group fails at eval instead of silently unboxing. The
  # derived array's order is definitional only — bar.cpp looks groups up by
  # id, and the lane token decides where the box renders.
  capsuleGroups = {
    stats = {
      foreground = "primary";
      members = [
        "sysmon-cpu"
        "sysmon-ram"
        "sysmon-temp"
      ];
    };
    net = {
      foreground = "secondary";
      members = [
        "bluetooth"
        "network"
      ];
    };
  };
  groupToken =
    id:
    assert capsuleGroups ? ${id};
    "group:${id}";

  # Stable pointers to the live wallpaper for consumers outside the shell
  # (scripts, screenshot tooling, anything that would otherwise parse the
  # sidecar). wallpaper_changed is one of only four hook events that carry
  # env vars, and it fires once per changed output. Hooks run under
  # `/bin/sh -lc` — a login shell, not fish — with stdio discarded, so the
  # script must be self-contained and self-evidently cheap.
  wallpaperChangedHook = pkgs.writeShellScript "noctalia-wallpaper-changed" ''
    set -eu
    dir="''${XDG_STATE_HOME:-$HOME/.local/state}/noctalia"
    mkdir -p "$dir"
    ln -sfn "$NOCTALIA_WALLPAPER_PATH" "$dir/wallpaper-$NOCTALIA_WALLPAPER_CONNECTOR"
    ln -sfn "$NOCTALIA_WALLPAPER_PATH" "$dir/wallpaper-current"
  '';

  # Config-directory layering: every *.toml directly in ~/.config/noctalia/
  # is a merge root, applied in filename sort order with later files winning
  # (config_service.cpp:381) — zz- sorts after config.toml, so this root
  # overrides it at noctalia's own merge. Same build-time validation as the
  # upstream module gives config.toml.
  tomlFormat = pkgs.formats.toml { };
  overridesFile =
    let
      raw = tomlFormat.generate "noctalia-zz-overrides.toml" cfg.overrides;
    in
    pkgs.runCommand "noctalia-zz-overrides-validated" { } ''
      ${getExe config.programs.noctalia.package} config validate ${raw}
      cp ${raw} $out
    '';

  hiddenAutostart = ''
    [Desktop Entry]
    Hidden=true
  '';

  # settings.toml (state dir) is deep-merged OVER the read-only config.toml
  # this module writes, so a runtime tweak to a table Nix declares wins
  # forever and makes later rebuilds look like no-ops. Drop exactly the
  # tables Nix owns on every activation and leave the rest — theme,
  # wallpaper.*, lockscreen_widgets and location are GUI-owned by decision,
  # as is the one key carved out of a Nix-owned table below (KEEP).
  prunePython = pkgs.python3.withPackages (ps: [ ps.tomli-w ]);
  pruneScript = pkgs.writeText "noctalia-prune-sidecar.py" ''
    import copy
    import os
    import sys
    import tomllib

    import tomli_w

    PRUNE = ("bar", "widget")

    # Dotted keys inside a PRUNE table that the settings GUI owns anyway.
    # BarConfig has no background *colour* — only one background_opacity, and
    # the fill is always the theme surface role, so a value that reads as
    # "tastefully transparent" over a dark surface is an unreadable white film
    # in light mode. There is no light/dark variant of [bar.main] and
    # BarMonitorOverride does not carry the key, so Nix has exactly one number
    # to give for both modes. The GUI knows which mode is live; Nix does not.
    KEEP = ("bar.main.background_opacity",)


    def take(data, path):
        node = data
        for part in path[:-1]:
            node = node.get(part)
            if not isinstance(node, dict):
                return None
        return node.get(path[-1])


    def put(data, path, value):
        node = data
        for part in path[:-1]:
            node = node.setdefault(part, {})
        node[path[-1]] = value


    def state_dir():
        for var, suffix in (("NOCTALIA_STATE_HOME", "noctalia"),
                            ("XDG_STATE_HOME", "noctalia"),
                            ("HOME", ".local/state/noctalia")):
            root = os.environ.get(var)
            if root:
                return os.path.join(root, suffix)
        return None


    root = state_dir()
    if root is None:
        sys.exit(0)
    path = os.path.join(root, "settings.toml")

    try:
        with open(path, "rb") as fh:
            data = tomllib.load(fh)
    except FileNotFoundError:
        sys.exit(0)
    except (OSError, tomllib.TOMLDecodeError) as err:
        print("noctalia: leaving %s alone (%s)" % (path, err), file=sys.stderr)
        sys.exit(0)

    removed = [key for key in PRUNE if key in data]
    if not removed:
        sys.exit(0)

    original = copy.deepcopy(data)

    kept = {}
    for dotted in KEEP:
        key = tuple(dotted.split("."))
        value = take(data, key)
        # TOML has no null, so a miss is unambiguous: leave the key absent and
        # let Nix's config.toml supply it until the GUI writes one.
        if value is not None:
            kept[key] = value

    for key in removed:
        del data[key]

    for key, value in kept.items():
        put(data, key, value)

    # A sidecar holding nothing but kept keys is already correct — don't
    # rewrite the file (or claim a prune) on every activation for no change.
    if data == original:
        sys.exit(0)

    tmp = path + ".nix-prune"
    with open(tmp, "wb") as fh:
        tomli_w.dump(data, fh)
    os.replace(tmp, path)
    print("noctalia: dropped Nix-owned table(s) from settings.toml: "
          + ", ".join(removed))
  '';

  defaultSettings = {
    shell = {
      telemetry_enabled = false;
      # shared_gl_context is left at its compiled default (true) — declaring it
      # here read as an NVIDIA workaround but was a no-op. Setting it to false
      # is the escape hatch if shell restarts ever kill Chromium/Electron GPU
      # procs (noctalia#3926).
      #
      # Launch apps through uwsm like every other launch path in this repo
      # (Hyprland binds, the old rofi drun-command) so they land in their own
      # uwsm-managed app scope instead of noctalia's cgroup.
      launch_apps_custom_command = "/run/current-system/sw/bin/uwsm-app -- $CMD";
      # The launcher's currency converter fetches ECB reference rates and a
      # Coinbase spot price at every start. Unused here, and both time out
      # after the full 10 s curl budget on this host, so it is pure startup
      # latency: `[http] download failed url=…eurofxref-daily.xml curl=28`.
      launcher.fetch_exchange_rates = false;
    };

    # Neither upower nor power-profiles-daemon exists on this host, and the
    # power_profile tile has no availability predicate upstream — only
    # weather / system-monitor / screen-time / clipboard are config-gated in
    # shortcut_registry.cpp — so the default tile renders and does nothing.
    # Declaring the list drops it and keeps upstream's order for the rest.
    # Wi-Fi stays: wlp8s0 exists, its radio is merely soft-blocked.
    #
    # This table is NOT pruned from the sidecar, so it is a seed: reordering
    # the tiles in the settings GUI pins them there and this list stops
    # mattering. That is the intended split, not a bug to chase.
    control_center.shortcuts = map (type: { inherit type; }) [
      "wifi"
      "bluetooth"
      "caffeine"
      "nightlight"
      "notification"
    ];

    # Seed only, and inert on any host that has already used the theme
    # picker: [theme] is GUI-owned (the sidecar wins, and the prune below
    # deliberately spares it), so this is what a fresh install starts from.
    # colorSource is the build-time half of the same choice — it also picks
    # the accent strategy above, which the GUI cannot reach.
    theme = {
      mode = "dark";
      source = if wallpaperMode then "wallpaper" else "builtin";
      builtin = "Tokyo-Night";
      wallpaper_scheme = "vibrant";
      # Nothing is selected in either template set, and while
      # enable_community_templates is true every start downloads the community
      # catalog and re-syncs all ~47 cached manifests — CommunityTemplateService
      # ::sync() returns early only on this flag, the empty communityIds list
      # does not spare the catalog fetch. Off until a template is selected.
      #
      # enable_builtin_templates is deliberately left at its default: with
      # builtin_ids empty the apply pass is already skipped, so turning it off
      # buys nothing. In particular it does NOT stop the undo sweep — on the
      # first apply after each start noctalia runs the undo hook of every
      # builtin template absent from builtin_ids, and with the flag false the
      # enabled set is merely empty, so the sweep still covers all of them
      # (template_apply_service.cpp: undoDisabledBuiltinTemplates, reached via
      # reconcileDisabledBuiltinIds whenever there is no previous request).
      # Those hooks are no-ops that fail loudly against home-manager's
      # read-only symlinks (`touch: cannot touch
      # '~/.config/wezterm/wezterm.lua': Permission denied`). There is no
      # config lever for it; see the unit Environment below for the one hook
      # that cost real time rather than just a log line.
      templates.enable_community_templates = false;
    };

    # Slice 3: the shell owns the wallpaper engine. Seeded from the repo-wide
    # addons.wallpaper option exactly like hyprpaper was (swaylock/hypridle
    # keep reading that option for the lock image until slice 5); the picker
    # directory is host-specific and comes in via cfg.settings.
    wallpaper = {
      enabled = true;
      default.path = toString config.custom.desktop.addons.wallpaper;
      # The default is all six transitions with one picked at random per
      # change; narrow to the cheapest on the 3840×2560 output. Key is
      # `transition`, singular, despite holding a list — and seed-only like
      # the rest of wallpaper.* (GUI-owned, never pruned): the sidecar holds
      # no transition key today, but one GUI tweak of the transition set
      # pins it there and this value stops mattering.
      transition = [ "fade" ];
    };
    # Slice 5: the shell owns locking and idle (PAM stack "login" — ships
    # with NixOS, no pam.d registration needed). Survived the 10x manual
    # lock/unlock gate; swaylock + hypridle are now disabled on the host
    # (one flip re-enables them for rollback).
    lockscreen = {
      enabled = true;
      # The login PAM stack runs pam_u2f as `auth sufficient` first, so a
      # YubiKey touch alone unlocks — but noctalia refuses to submit an
      # empty password unless this is set, which would force typing a
      # password on every unlock. Empty submit + touch = the swaylock flow.
      allow_empty_password = true;
      # Parity with swaylock --image: the lock background is the same
      # wallpaper, not noctalia's default plain scrim.
      wallpaper = toString config.custom.desktop.addons.wallpaper;
    };
    # Parity with the old hypridle "pc" profile: lock at 10 min, DPMS off
    # at 15 min, no suspend. Every field must be spelled out: [idle.behavior.*]
    # in the config REPLACES noctalia's named defaults (namedMap parses each
    # entry from bare struct defaults — timeout 0, action "" — so a partial
    # entry is silently dropped or warned "needs an action").
    idle.behavior = {
      lock = {
        enabled = true;
        timeout = 600;
        action = "lock";
      };
      screen-off = {
        enabled = true;
        timeout = 900;
        action = "screen_off";
      };
    };

    notification = {
      enable_daemon = true;
      layer = "overlay";
      # Frosted like the bar, not the near-solid 0.97 default. The Hyprland
      # layer rule already blurs the noctalia-notification namespace, so what
      # shows through the card is blur, not raw desktop — text stays legible
      # well below the opacity the plain default needs. Effective only while
      # the GUI has never written [notification] into the sidecar (it hasn't;
      # this table is deliberately not pruned).
      background_opacity = 0.35;
    };

    osd = {
      position = "top_right";
      # mz is a desktop: no backlight, ddcutil disabled — drop brightness OSD.
      kinds.brightness = false;
    };

    # Sampler cadence. A poll of 0 disables that metric entirely — no
    # sampling, no wakeups (non-zero values are clamped to [1, 120] at
    # consumption). Nothing on this host displays a gpu or disk stat, and
    # killing the gpu poll also guards against noctalia#3603 (sysmon keeping
    # the NVIDIA dGPU awake) should a panel ever surface one. cpu / memory /
    # network stay at their 2/2/3 s defaults — the sysmon plugin redraws at
    # 2 s, matching. Like control_center.shortcuts this table is NOT pruned
    # from the sidecar, so it is a seed the settings GUI can outrank.
    #
    # cpu_temp_sensor_path is deliberately NOT pinned: a configured value must
    # be a literal existing temp*_input file (readConfiguredSensor rejects
    # anything else), and the hwmon index is not boot-stable here — k10temp
    # was hwmon4 under waybar and hwmon2 on 2026-08-21. The autodetect scans
    # by driver *name* and ranks k10temp/Tctl first (cpu_temp_sensor.cpp,
    # knownDriverPriority = 0), so it lands on the right sensor every boot;
    # a pinned path would break at random ones.
    system.monitor = {
      gpu_poll_seconds = 0;
      disk_poll_seconds = 0;
    };

    # The one hook worth having. wallpaper_changed both fires reliably
    # (colors_changed over-fires — noctalia#3814) and carries env vars; the
    # script keeps stable symlinks under ~/.local/state/noctalia/:
    # wallpaper-<connector> per output plus wallpaper-current, where the last
    # output to change wins. Seed table like the rest — not pruned, so a hook
    # edited in the settings GUI outranks this one.
    hooks.wallpaper_changed = [ "${wallpaperChangedHook}" ];

    # Slice 4: named widget instances referenced from bar.main below. The
    # sysmon instances use the sab/sysmon plugin rather than the builtin
    # sysmon widget because the builtin's hover tooltip has no filtering —
    # it always lists all 16 stats. The plugin reads the same sampler
    # (noctalia.systemStats(), k10temp autodetected) and shows only its own
    # stat's rows.
    widget = recursiveUpdate (
      {
        # Waybar's hyprland/workspaces had `active-only = false` plus a
        # window-rewrite glyph per app — every workspace visible at once, each
        # showing what is running in it. noctalia's `workspaces` widget cannot
        # do that (icons exist only on the focused pill), so the left lane uses
        # `taskbar` in grouped mode instead: one capsule per workspace holding
        # that workspace's app icons, with the workspace number inside it.
        # Clicking a workspace badge still activates the workspace.
        #
        # Empty workspaces only appear if Hyprland keeps reporting them, hence
        # desktop.hyprland.workspaces.persistent on the host.
        taskbar = {
          group_by_workspace = true;
          workspace_group_content = "icons";
          workspace_group_capsule = true;
          show_workspace_label = true;
          workspace_label_placement = "inside";
          # Waybar's active workspace was unmissable — `button.active` drew a
          # filled pill while the rest stayed plain text. minimal = true was
          # tried first (bare tinted numbers, no disc) and at 22px the tints
          # are too close to tell active from occupied from empty. minimal
          # off restores the filled disc: taskbar_widget.cpp fills each badge
          # with workspaceFillColor() and picks the number's colour via
          # readableColorForFill(), so the active number sits on a solid
          # focused_color puck with guaranteed-contrast text.
          minimal = false;
          # Only the active badge should pop, waybar-style. The upstream
          # occupied/empty default is the secondary role — a bright pastel in
          # both palette modes, which turns nine persistent workspaces into a
          # row of loud pucks. Muted fills instead: readableColorForFill pairs
          # a role fill with its on_* role, so surface_variant still yields a
          # legible on_surface_variant number; empty badges are additionally
          # faded to 55% alpha by the widget itself. Theme mode mirrors
          # vu-neon waybar: cyan active, elevated (the old button.active
          # background) for occupied, overlay0 (the old empty text) for empty.
          focused_color = if wallpaperMode then "primary" else hex "cyan";
          occupied_color = if wallpaperMode then "surface_variant" else hex "elevated";
          empty_color = if wallpaperMode then "surface_variant" else hex "overlay0";
          hide_empty_workspaces = false;
          # Per-output bar: show only this monitor's workspaces, like waybar did.
          show_all_outputs = false;
          icon_scale = 0.85;
          item_spacing = 3;
          # Default taskbar scroll cycles *windows*; waybar's workspace module
          # scrolled between workspaces. Left/middle stay reserved by the widget
          # (activate / close a task).
          actions = {
            scroll_up = "workspace-switch prev";
            scroll_down = "workspace-switch next";
          };
        };

        # "Time and clock": date and time in one line (the bar is a single
        # 22px row), full date on hover. No calendar grid — tooltip_format is
        # a plain strftime string with no {calendar} token and no markup; the
        # calendar itself is one click away in the control center.
        clock = {
          format = "{:%b %d  %H:%M}";
          tooltip_format = "{:%A, %d %B %Y}";
        };

        # One-click palette reshuffle — with colorSource = "wallpaper" the
        # whole bar re-tints from the new image. Action values are the bar's
        # own grammar: a bare word is an in-process IPC verb (`exec …` would
        # be a shell command), resolved at bind time rather than by `noctalia
        # config validate` — a typo'd verb builds fine and only shows up as a
        # runtime log line. Glyph names are Tabler icons plus noctalia's
        # curated aliases; "shuffle" is the arrows-shuffle alias.
        wallpaper-shuffle = {
          type = "custom_button";
          glyph = "shuffle";
          tooltip = "Random wallpaper";
          actions = {
            left = "wallpaper-random";
            right = "panel-toggle wallpaper";
          };
        };

        sysmon-cpu = {
          type = "sab/sysmon:meter";
          stat = "cpu";
        };
        sysmon-temp = {
          type = "sab/sysmon:meter";
          stat = "temp";
        };
        sysmon-ram = {
          type = "sab/sysmon:meter";
          stat = "ram";
        };
      }
      # mic-vu click/scroll gestures (mute, pavucontrol, gain steps) are
      # declared as manifest defaults in plugins/mic_vu/plugin.toml — the
      # widget-settings schema warns on a config-level actions table. It also
      # renders a pre-coloured SVG face, so it takes no `color` either.
      // optionalAttrs cfg.micVuMeter.enable {
        mic-vu.type = "sab/mic_vu:meter";
      }
    ) widgetAccents;

    # Declarative plugin state: no git sources, no background updates — the
    # only source is the Nix store path built above. Declaring ANY explicit
    # [[plugins.source]] replaces the two seeded git catalogs (official →
    # noctalia-dev/official-plugins, community → noctalia-dev/community-plugins;
    # config_service.cpp seeds them only when the TOML declares no array), so
    # the plugin browser in the settings GUI is empty BY DESIGN — hermetic
    # Nix-only plugins. Re-declare a git source alongside this one to get the
    # catalogs back.
    plugins = {
      auto_update = "none";
      enabled = [ "sab/sysmon" ] ++ optional cfg.micVuMeter.enable "sab/mic_vu";
      source = [
        {
          name = "dotnix";
          kind = "path";
          location = "${pluginSource}";
          enabled = true;
        }
      ];
    };

    bar.main = {
      position = "top";
      # Geometry is deliberately NOT waybar-parity — waybar was a 30px bar at
      # rgba(11,15,26,0.85) floating 10px off every edge (`margin 10 10 0 10`
      # + @bar-op in vu-neon.css) and that got rejected in favour of these,
      # tuned live in the settings GUI: thinner, near-transparent so the
      # wallpaper reads through, full-width and nearly flush with the top
      # edge. They live here now because the activation prune below makes Nix
      # authoritative over [bar.main] — left in the sidecar they'd be dropped.
      # Everything else in this file still chases the waybar look.
      thickness = 22;
      background_opacity = 0.29;
      radius = 0;
      margin_ends = 0;
      margin_edge = 3;
      padding = 8;
      shadow = false;
      # The old waybar CSS boxed related modules together — `group/stats`
      # (cpu/memory/temperature) and `group/network` (bluetooth/network) each
      # drew one outlined container. capsule_group is the direct analogue: a
      # `group:<id>` token in a lane renders its members inside one box.
      # Members give up their own capsule_* (bar.cpp hands them the group's),
      # but per-widget `color` survives — so theme mode keeps a neon hue per
      # module over a neutral box, and wallpaper mode tints the whole box.
      # Definitions live once in capsuleGroups above; lanes reference them
      # through groupToken.
      capsule_group = mapAttrsToList (
        id: group: mkCapsuleGroup id group.foreground group.members
      ) capsuleGroups;
      # Near-waybar layout: workspaces + window title on the left, and the
      # old modules-right set (language, mic VU, volume, stats cpu/ram/temp,
      # bluetooth, network, tray, power). Launcher / wallpaper / media /
      # clipboard widgets are dropped from the bar like they were absent
      # from waybar; those panels stay reachable via keybinds, IPC, and the
      # control-center kept before session. The notification-history bell is
      # the one panel that earned a button back. Desktop machine: no
      # battery/brightness widgets.
      start = [
        "taskbar"
        "active_window"
      ];
      center = [ "clock" ];
      # One deliberate departure from waybar's order: it ran
      # language, [stats], mic-vu, volume, [network] — loose widgets wedged
      # between the two boxes, which reads as orphaned rather than as a
      # third group. Ungrouped widgets come first here, boxes after, so the
      # absence of a box means "standalone" instead of "left over". mic-vu and
      # volume are not boxed together: the meter draws a pre-coloured SVG and
      # cannot take a group foreground, and in wallpaper mode a third group
      # would have to reuse `tertiary` — the keyboard_layout hue.
      # wallpaper-shuffle and theme_mode (a builtin whose left-click already
      # defaults to theme-mode-toggle) sit with the controls cluster; neither
      # gets a widgetAccents entry, so both keep the on-surface role in either
      # color mode.
      end = [
        "keyboard_layout"
      ]
      ++ optional cfg.micVuMeter.enable "mic-vu"
      ++ [
        "volume"
        (groupToken "stats")
        (groupToken "net")
        "tray"
        "wallpaper-shuffle"
        "theme_mode"
        "control-center"
        "notifications"
        "session"
      ];
    };
  };
in
{
  # Deliberately NOT gated on isLinux: `pkgs` is config-dependent in
  # home-manager, so using it in `imports` is infinite recursion. Upstream
  # defaults `programs.noctalia.package` to a Linux-only flake package, but
  # option defaults are lazy — mba13 evaluates as long as nothing forces
  # every option value (verified: its toplevel drvPath evaluates).
  imports = [ inputs.noctalia.homeModules.default ];

  options.custom.desktop.addons.noctalia = with types; {
    enable = mkBoolOpt false "Whether to enable the noctalia desktop shell.";

    settings = mkOpt (attrsOf anything) { } ''
      Noctalia config.toml as a Nix attrset, recursively merged over the
      module defaults (host values win; lists replace, not concatenate).
      Validated at build time by `noctalia config validate`.
    '';

    overrides = mkOpt (attrsOf anything) { } ''
      A second noctalia config root, written to
      ~/.config/noctalia/zz-overrides.toml and validated at build time.
      Every *.toml directly in the config directory is a merge root, applied
      in filename sort order with later files winning — so these values beat
      config.toml (defaults + `settings`) at noctalia's own runtime merge,
      with arrays replaced wholesale. The sidecar settings.toml still outranks
      both outside the pruned tables.

      Differs from `settings` in when the merge happens: `settings` is folded
      into config.toml at eval time, `overrides` stays a separate file the
      shell layers at startup — useful for values you want legible as "this
      host deviates here" rather than fused into the big table, and for A/B
      experiments: a hand-dropped ~/.config/noctalia/zz-test.toml layers the
      same way with no rebuild at all (the directory is real, only the
      individual files are store symlinks).
    '';

    colorSource =
      mkOpt
        (enum [
          "theme"
          "wallpaper"
        ])
        "theme"
        ''
          Where bar accents come from. "theme" paints each widget a literal hue
          from custom.theme.colors (waybar-parity, seven fixed neons). "wallpaper"
          hands colour to the wallpaper-derived M3 palette, which has only three
          accent roles plus error — so accents move from the widget to the capsule
          group and follow the wallpaper as it changes.

          This also seeds theme.source, but only seeds it: [theme] is left to the
          settings GUI, so switching the runtime palette there and leaving this at
          its default is expected, not a mismatch to fix.
        '';

    customPalettes = mkOpt (attrsOf anything) { } ''
      Custom JSON palettes, keyed by palette name; passed through to
      programs.noctalia.customPalettes.
    '';

    micVuMeter = {
      enable = mkBoolOpt false ''
        Whether to enable the mic VU meter bar widget (Luau plugin that
        streams the microphone through pw-cat and renders the old waybar
        akg-vu-meter's analog needle-over-arc SVG face).
      '';

      sourceMatch = mkOpt str "AKG_C44" ''
        Substring (awk regex) matched against `pactl list sources short`
        node names to pick the microphone to meter. Monitor sources are
        excluded before the match, so a device name is enough — it will not
        resolve to that device's own playback loopback.
      '';
    };
  };

  config = mkIf cfg.enable ({
    programs.noctalia = {
      enable = true;
      systemd.enable = true;
      validateConfig = true;
      settings = recursiveUpdate defaultSettings cfg.settings;
      customPalettes = cfg.customPalettes;
    };

    # The shell is the only locker on the host: keep systemd retrying
    # instead of giving up after the default 5-crash burst, which would
    # silently leave the workstation without idle-lock.
    systemd.user.services.noctalia = {
      Unit.StartLimitIntervalSec = 0;
      Unit.X-Restart-Triggers = optional (
        cfg.overrides != { }
      ) "${config.xdg.configFile."noctalia/zz-overrides.toml".source}";
      Service.RestartSec = 2;
      # Blunt the one builtin-template undo hook that costs more than a log
      # line (see [theme.templates] above for why the sweep cannot be turned
      # off). starship's hook discovers its config by checking $STARSHIP_CONFIG,
      # then `systemctl --user show-environment`, and only then by reading
      # /proc/<pid>/environ for *every* process owned by the user — which has
      # already been killed on the hook timeout here (exit code 143). Handing
      # it the path it would have defaulted to anyway makes it return on the
      # first branch. Scoped to this unit, so fish and starship itself are
      # untouched; harmless even if the file is absent, since the hook then
      # simply finds nothing to undo.
      Service.Environment = [
        "STARSHIP_CONFIG=${config.home.homeDirectory}/.config/starship.toml"
      ];
    };

    # Give the declaration above authority over the tables it declares: the
    # app's sidecar outranks config.toml, so without this a single drag of
    # the bar thickness in the settings GUI silently pins it forever. Runs
    # before the shell restarts, and never touches the GUI-owned tables.
    home.activation.noctaliaPruneSidecar = config.lib.dag.entryAfter [ "writeBoundary" ] ''
      run ${prunePython}/bin/python3 ${pruneScript}
    '';

    # Mask the GTK tray applets whose job noctalia's own widgets took over.
    # Both ship an /etc/xdg/autostart entry (networkmanagerapplet and blueman
    # are in systemPackages for their CLI/editor halves), uwsm's XDG-autostart
    # generator turns those into app-<name>@autostart.service, and the result
    # is a second NM/BT indicator inside the `tray` widget duplicating the
    # `network` and `bluetooth` capsules. XDG spec: Hidden=true in the
    # higher-priority ~/.config/autostart means "treat as absent".
    xdg.configFile = {
      # The extra config root (see the overrides option). Upstream's
      # X-Restart-Triggers only watches config.toml and the palettes, so the
      # unit gets its own trigger for this file below.
      "noctalia/zz-overrides.toml" = mkIf (cfg.overrides != { }) { source = overridesFile; };
      "autostart/nm-applet.desktop".text = hiddenAutostart;
    }
    # waybar's module carries the same blueman mask, and xdg.configFile.<n>.text
    # merges by concatenation rather than erroring — so only claim it while
    # waybar is off, which is the normal state whenever noctalia owns the bar.
    // optionalAttrs (!config.custom.desktop.addons.waybar.enable) {
      "autostart/blueman.desktop".text = hiddenAutostart;
    };

    # notify-send for the modules that shell out to it; the daemon side used
    # to come from mako, which is disabled while noctalia owns notifications.
    home.packages = with pkgs; [ libnotify ];
  });
}
