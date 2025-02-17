{
  inputs,
  pkgs,
  config,
  lib,
  ...
}:
with lib;
with lib.custom; let
  cfg = config.custom.desktop.addons.wezterm;
in {
  options.custom.desktop.addons.wezterm = {
    enable = mkEnableOption "Whether to enable the wezterm terminal";
  };

  config = mkIf cfg.enable {
    programs.wezterm = {
      enable = true;
      # package = inputs.wezterm.packages.${pkgs.system}.default;
      extraConfig =
        # Generate wezterm.lua; order of files are important
        (builtins.readFile ./wezterm.lua)
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
