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
  #   slice 5: lock + idle                 (swaylock/hypridle off)  — PAM risk, LAST
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
    lockscreen.enabled = false; # slice 5 — swaylock still owns locking
    idle.behavior = {
      # slice 5 — hypridle still owns idle; never enable idle-lock before the
      # lock screen survived 10x manual lock/unlock (fails closed via PAM).
      lock.enabled = false;
      screen-off.enabled = false;
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
        "media"
        "tray"
        "notifications"
        "clipboard"
        "keyboard_layout"
        "network"
        "bluetooth"
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
