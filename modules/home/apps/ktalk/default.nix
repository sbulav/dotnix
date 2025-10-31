{
  lib,
  config,
  pkgs,
  namespace,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf;

  cfg = config.custom.apps.ktalk;
in
{
  options.custom.apps.ktalk = {
    enable = mkEnableOption "ktalk";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      pkgs.${namespace}.ktalk
    ];
  };
}
