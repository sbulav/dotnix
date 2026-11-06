{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.custom.tools.disktree;
in
{
  options.custom.tools.disktree = {
    enable = mkEnableOption "disktree";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [ unstable.disktree ];
  };
}
