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
    # at 15 min, no suspend (lock-and-suspend keeps its disabled default).
    idle.behavior = {
      lock.enabled = true; # default timeout 600
      screen-off = {
        enabled = true;
        timeout = 900; # noctalia default is 660; hypridle pc used 900
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
      mic-vu.type = "sab/mic_vu:meter";
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
