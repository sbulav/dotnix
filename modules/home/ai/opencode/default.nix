{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf;

  cfg = config.custom.ai.opencode;
in {
  options.custom.ai.opencode = {
    enable = mkEnableOption "Enable opencode AI assistent";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      opencode
    ];
  };
}
