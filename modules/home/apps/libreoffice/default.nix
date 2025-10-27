{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf;

  cfg = config.custom.apps.libreoffice;
in {
  options.custom.apps.libreoffice = {
    enable = mkEnableOption "Enable libreoffice app";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      libreoffice
    ];
  };
}
