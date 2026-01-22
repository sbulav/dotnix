{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf;

  cfg = config.custom.tools.tea;
in
{
  options.custom.tools.tea = {
    enable = mkEnableOption "tea";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      unstable.tea
    ];
  };
}
