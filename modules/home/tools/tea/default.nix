{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf;

  cfg = config.custom.tools.tea;
in {
  options.custom.tools.tea = {
    enable = mkEnableOption "argocd";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      tea
    ];
  };
}
