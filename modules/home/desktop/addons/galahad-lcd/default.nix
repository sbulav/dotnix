{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.desktop.addons.galahad-lcd;
  noctalia = config.custom.desktop.addons.noctalia;

  # glc's config is a *rendered* file, not a store symlink: noctalia rewrites
  # it from the template below on every palette change (wallpaper switch,
  # theme switch, dark/light flip) and on its first apply after each start.
  # It therefore lives in the state dir, and glc polls it (mtime) rather
  # than being restarted — the USB device is only reset on process exit.
  stateDir = "${config.xdg.stateHome}/glc";
  configPath = "${stateDir}/config.toml";

  # colors_changed is the obvious hook but carries no palette data (and
  # over-fires, noctalia#3814); a user template gets the resolved Material
  # roles for free and is skipped by noctalia when the output is unchanged.
  # `{{ image }}` is the palette's source image — empty for builtin and
  # community palettes, where the wallpaper_changed hook's symlink stands in.
  token = role: "{{ colors.${role}.default.hex }}";
  template = pkgs.writeText "glc-config.toml.tmpl" ''
    # Rendered by noctalia from the galahad-lcd home-manager template.
    # Do not edit: every palette change rewrites it, and glc hot-reloads it.
    rgb = "${token cfg.roles.pump}"
    fps = ${toString cfg.fps}
    <* if {{ image }} *>
    bg = "{{ image }}"
    <* else *>
    bg = "${config.xdg.stateHome}/noctalia/wallpaper-current"
    <* endif *>
    bg_mode = "${cfg.bgMode}"
    overlay = ${boolToString cfg.overlay}
    overlay_opacity = ${toString cfg.overlayOpacity}

    [colors]
    time = "${token cfg.roles.time}"
    date = "${token cfg.roles.date}"
    cpu_temp = "${token cfg.roles.cpu_temp}"
    cpu_usage = "${token cfg.roles.cpu_usage}"
    overlay = "${token cfg.roles.overlay}"
    background = "${token cfg.roles.background}"
    panel = "${token cfg.roles.panel}"
    ${cfg.extraConfig}
  '';
in
{
  options.custom.desktop.addons.galahad-lcd = with types; {
    enable = mkBoolOpt false ''
      Drive the Lian Li Galahad II LCD pump (USB 0416:7395) with glc and keep
      its LCD overlay and pump RGB in step with the noctalia palette. Needs
      the udev rule granting the user access to the device (see the mz
      system config) and custom.desktop.addons.noctalia.
    '';

    package =
      mkOpt package inputs.galahad-linux-control.packages.${pkgs.stdenv.hostPlatform.system}.default
        "The glc package.";

    fps = mkOpt ints.positive 5 "LCD refresh rate; every frame is an ffmpeg encode, keep it low.";

    bgMode = mkOpt (enum [
      "stretch"
      "fit"
      "fill"
    ]) "fill" "How the wallpaper is scaled onto the 480x480 LCD.";

    overlay = mkBoolOpt true "Draw the clock/date/CPU overlay over the wallpaper.";

    overlayOpacity = mkOpt (ints.between 0 255) 150 "Opacity of the panel behind the overlay text.";

    roles = mkOpt (attrsOf str) {
      pump = "primary";
      time = "primary";
      date = "on_surface_variant";
      cpu_temp = "tertiary";
      cpu_usage = "secondary";
      overlay = "surface";
      background = "surface";
      panel = "surface_container";
    } "Which noctalia Material color token colours each glc element (pump RGB plus the [colors] keys).";

    extraConfig =
      mkOpt lines ""
        "Raw lines appended to the rendered glc config (noctalia template syntax allowed).";
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = noctalia.enable;
        message = "custom.desktop.addons.galahad-lcd renders its config through noctalia; enable custom.desktop.addons.noctalia.";
      }
    ];

    home.packages = [ cfg.package ];

    # Seed table like the noctalia module's own: [theme] is GUI-owned in the
    # sidecar, but the sidecar is deep-merged over config.toml and never
    # carries this key, so the template survives GUI edits to [theme].
    custom.desktop.addons.noctalia.settings.theme.templates.user.glc = {
      input_path = "${template}";
      output_path = "$XDG_STATE_HOME/glc/config.toml";
    };

    systemd.user.services.galahad-lcd = {
      Unit = {
        Description = "Lian Li Galahad II LCD (glc), palette-driven via noctalia";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        # A missing config is non-fatal (defaults until noctalia renders it);
        # a missing device exits non-zero, so on-failure keeps retrying it.
        ExecStart = "${cfg.package}/bin/glc --config ${configPath}";
        Restart = "on-failure";
        RestartSec = 10;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
