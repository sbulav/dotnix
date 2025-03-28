{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf;

  cfg = config.custom.tools.yandex-cloud;
in {
  options.custom.tools.yandex-cloud = {
    enable = mkEnableOption "yandex-cloud";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      yandex-cloud
    ];
  };
}
