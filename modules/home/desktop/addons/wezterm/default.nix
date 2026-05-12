{
  inputs,
  pkgs,
  config,
  lib,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.desktop.addons.wezterm;
  c = config.custom.theme.colors;
in
{
  options.custom.desktop.addons.wezterm = {
    enable = mkEnableOption "Whether to enable the wezterm terminal";

    status = {
      kubernetes = {
        enable = mkBoolOpt true "Whether to show Kubernetes context in the WezTerm status bar";
        refreshSeconds = mkOpt types.ints.positive 15 "How often to refresh Kubernetes status, in seconds";
      };

      clock = {
        enable = mkBoolOpt true "Whether to show the clock in the WezTerm status bar";
        format = mkOpt types.str "%H:%M" "strftime format for the WezTerm status bar clock";
      };
    };
  };

  config = mkIf cfg.enable {
    programs.wezterm = {
      enable = true;
      # package = inputs.wezterm.packages.${pkgs.stdenv.hostPlatform.system}.default;
      extraConfig =
        # Generate wezterm.lua; order of files are important
        ''
          local custom_theme = {
            base = "#${c.base}",
            panel = "#${c.panel}",
            elevated = "#${c.elevated}",
            text = "#${c.text}",
            subtext = "#${c.subtext}",
            separator = "#${c.separator}",
            cyan = "#${c.cyan}",
            pink = "#${c.pink}",
            violet = "#${c.violet}",
            mint = "#${c.mint}",
            amber = "#${c.amber}",
            blue = "#${c.blue}",
            overlay0 = "#${c.overlay0}",
            overlay1 = "#${c.overlay1}",
            overlay2 = "#${c.overlay2}",
          }

          local custom_status = {
            kubernetes = {
              enabled = ${builtins.toJSON cfg.status.kubernetes.enable},
              refresh_seconds = ${toString cfg.status.kubernetes.refreshSeconds},
            },
            clock = {
              enabled = ${builtins.toJSON cfg.status.clock.enable},
              format = ${builtins.toJSON cfg.status.clock.format},
            },
          }
        ''
        + (builtins.readFile ./wezterm.lua)
        + (builtins.readFile ./mappings.lua)
        + (builtins.readFile ./colors.lua)
        + (builtins.readFile ./tabs.lua)
        + (builtins.readFile ./status.lua)
        + (builtins.readFile ./events.lua)
        + ''
          return config
        '';
    };
  };
}
