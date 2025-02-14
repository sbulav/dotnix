{
  config,
  lib,
  pkgs,
  namespace,
  ...
}: let
  inherit (lib) mkIf;
  inherit (lib.${namespace}) mkBoolOpt;

  cfg = config.${namespace}.tools.wine;
in {
  options.${namespace}.tools.wine = {
    enable = mkBoolOpt false "Whether or not to enable Wine.";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      wineWowPackages.waylandFull
      # wine64Packages.waylandFull
      # winePackages.waylandFull
      winetricks
    ];
  };
}
