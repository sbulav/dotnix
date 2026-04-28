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
        ''
        + (builtins.readFile ./wezterm.lua)
        + (builtins.readFile ./mappings.lua)
        + (builtins.readFile ./colors.lua)
        + (builtins.readFile ./tabs.lua)
        + (builtins.readFile ./events.lua)
        + ''
          return config
        '';
    };
  };
}
