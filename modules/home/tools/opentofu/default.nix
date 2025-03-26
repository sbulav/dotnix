{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf;

  cfg = config.custom.tools.opentofu;
in {
  options.custom.tools.opentofu = {
    enable = mkEnableOption "opentofu";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      opentofu
    ];
  };
}
