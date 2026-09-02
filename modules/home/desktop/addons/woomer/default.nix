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
  cfg = config.custom.desktop.addons.woomer;
in
{
  options.custom.desktop.addons.woomer = {
    enable = mkBoolOpt false "Whether to enable woomer (Wayland zoomer) and its keybindings.";
  };

  config = mkIf cfg.enable {
    home.packages = [
      inputs.woomer.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];

    custom.desktop.hyprland.keybindings.woomer = "Z";
  };
}
