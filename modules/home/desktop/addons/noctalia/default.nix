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
  #   slice 1: bar + notifications + OSD   (waybar/mako off)
  #   slice 2: launcher + session/power    (rofi/wlogout off)
  #   slice 3: wallpaper engine + palette  (hyprpaper/waypaper off)
  #   slice 5: lock + idle                 (swaylock/hypridle off) — PAM risk, LAST
  defaultSettings = {
    shell = {
      telemetry_enabled = false;
      # Trial runs on NVIDIA: keep the shared GL context (default); flip to
      # false if shell restarts kill Chromium/Electron GPU procs (noctalia#3926).
      shared_gl_context = true;
    };

    # Fixed palette from day one — no wallpaper-derived color by decision.
    theme = {
      mode = "dark";
      source = "builtin";
      builtin = "Tokyo-Night";
    };

    wallpaper.enabled = false; # slice 3 — hyprpaper still owns wallpaper
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
      # Desktop machine: no battery/brightness widgets. Widgets for surfaces
      # the shell does not own yet arrive with their slice: launcher + session
      # in slice 2 (rofi/wlogout still active), wallpaper in slice 3.
      start = [ "workspaces" ];
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
