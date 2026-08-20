{
  options,
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
  pluginSource = pkgs.runCommand "noctalia-plugins-dotnix" { } ''
    mkdir -p $out
    cp -r ${./plugins/mic_vu} $out/mic_vu
    cp -r ${./plugins/sysmon} $out/sysmon
    chmod -R u+w $out
    substituteInPlace $out/mic_vu/plugin.toml \
      --replace-fail '@SOURCE_MATCH@' ${escapeShellArg cfg.micVuMeter.sourceMatch}
    substituteInPlace $out/mic_vu/service.luau \
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
    ];
    text = ''
      set -uo pipefail

      action="''${1:-status}"
      hint="string:x-canonical-private-synchronous:akg-mic"
      timeout=1500

      src=$(pactl list sources short 2>/dev/null \
        | gawk -v m=${escapeShellArg cfg.micVuMeter.sourceMatch} '$0 ~ m { print $2; exit }')
      if [ -z "$src" ]; then src="@DEFAULT_SOURCE@"; fi

      read_state() {
        local vol muted
        vol=$(pactl get-source-volume "$src" 2>/dev/null \
          | gawk -F/ 'NR == 1 { gsub(/[ %]/, "", $2); print $2; exit }')
        case "$(pactl get-source-mute "$src" 2>/dev/null)" in
          *yes*) muted=1 ;;
          *) muted=0 ;;
        esac
        printf '%s %s\n' "''${vol:-0}" "$muted"
      }

      notify_state() {
        local title body icon vol muted
        read -r vol muted < <(read_state)
        if [[ "$muted" == "1" ]]; then
          icon="microphone-sensitivity-muted"
          title="🎤 Mic muted"
          body="gain ''${vol}% (no signal)"
        else
          icon="microphone-sensitivity-high"
          title="🎤 Mic active"
          body="gain ''${vol}%"
        fi
        notify-send -t "$timeout" -h "$hint" -i "$icon" "$title" "$body" || true
      }

      case "$action" in
        mute)
          pactl set-source-mute "$src" toggle
          notify_state
          ;;
        vol-up)
          pactl set-source-volume "$src" +5%
          read -r vol _ < <(read_state)
          if [ "''${vol:-0}" -gt 100 ]; then
            pactl set-source-volume "$src" 100%
          fi
          notify_state
          ;;
        vol-down)
          pactl set-source-volume "$src" -5%
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

  defaultSettings = {
    shell = {
      telemetry_enabled = false;
      # Trial runs on NVIDIA: keep the shared GL context (default); flip to
      # false if shell restarts kill Chromium/Electron GPU procs (noctalia#3926).
      shared_gl_context = true;
      # Launch apps through uwsm like every other launch path in this repo
      # (Hyprland binds, the old rofi drun-command) so they land in their own
      # uwsm-managed app scope instead of noctalia's cgroup.
      launch_apps_custom_command = "/run/current-system/sw/bin/uwsm-app -- $CMD";
    };

    # Fixed palette from day one — no wallpaper-derived color by decision.
    theme = {
      mode = "dark";
      source = "builtin";
      builtin = "Tokyo-Night";
    };

    # Slice 3: the shell owns the wallpaper engine. Seeded from the repo-wide
    # addons.wallpaper option exactly like hyprpaper was (swaylock/hypridle
    # keep reading that option for the lock image until slice 5); the picker
    # directory is host-specific and comes in via cfg.settings.
    wallpaper = {
      enabled = true;
      default.path = toString config.custom.desktop.addons.wallpaper;
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
    };

    osd = {
      position = "top_right";
      # mz is a desktop: no backlight, ddcutil disabled — drop brightness OSD.
      kinds.brightness = false;
    };

    # Slice 4: named widget instances referenced from bar.main below. The
    # sysmon instances use the sab/sysmon plugin rather than the builtin
    # sysmon widget because the builtin's hover tooltip has no filtering —
    # it always lists all 16 stats. The plugin reads the same sampler
    # (noctalia.systemStats(), k10temp autodetected) and shows only its own
    # stat's rows.
    widget = {
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
    // optionalAttrs cfg.micVuMeter.enable {
      mic-vu = {
        type = "sab/mic_vu:meter";
        # Same interactions the waybar meter had. Luau bar widgets expose no
        # click/scroll callbacks; the declarative gesture map is the only
        # interaction mechanism for plugin widgets.
        actions = {
          left = "exec ${micCtl}/bin/akg-mic-ctl mute";
          right = "exec ${pkgs.pavucontrol}/bin/pavucontrol -t 3";
          scroll_up = "exec ${micCtl}/bin/akg-mic-ctl vol-up";
          scroll_down = "exec ${micCtl}/bin/akg-mic-ctl vol-down";
        };
      };
    };

    # Declarative plugin state: no git sources, no background updates — the
    # only source is the Nix store path built above.
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
      # Desktop machine: no battery/brightness widgets.
      start = [
        "launcher"
        "wallpaper"
        "workspaces"
      ];
      center = [ "clock" ];
      end = [
        "sysmon-cpu"
        "sysmon-temp"
        "sysmon-ram"
        "media"
        "tray"
        "notifications"
        "clipboard"
        "keyboard_layout"
        "network"
        "bluetooth"
      ]
      ++ optional cfg.micVuMeter.enable "mic-vu"
      ++ [
        "volume"
        "control-center"
        "session"
      ];
    };
  };
in
{
  imports = [ inputs.noctalia.homeModules.default ];

  options.custom.desktop.addons.noctalia = with types; {
    enable = mkBoolOpt false "Whether to enable the noctalia desktop shell.";

    settings = mkOpt (attrsOf anything) { } ''
      Noctalia config.toml as a Nix attrset, recursively merged over the
      module defaults (host values win; lists replace, not concatenate).
      Validated at build time by `noctalia config validate`.
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
        names to pick the microphone to meter.
      '';
    };
  };

  config = mkIf cfg.enable {
    programs.noctalia = {
      enable = true;
      systemd.enable = true;
      validateConfig = true;
      settings = recursiveUpdate defaultSettings cfg.settings;
      customPalettes = cfg.customPalettes;
    };

    # notify-send for the modules that shell out to it; the daemon side used
    # to come from mako, which is disabled while noctalia owns notifications.
    home.packages = with pkgs; [ libnotify ];
  };
}
