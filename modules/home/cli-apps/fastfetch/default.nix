{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf;

  cfg = config.custom.cli-apps.fastfetch;
in
{
  options.custom.cli-apps.fastfetch = {
    enable = mkEnableOption "Fastfetch";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      fastfetch
    ];
    home.shellAliases = {
      neofetch = "fastfetch";
    };
  };
}
