{
  lib,
  config,
  namespace,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.${namespace}.security.sops;
in {
  options.${namespace}.security.sops = {
    enable = mkEnableOption "SOPS secrets management for home-manager";
    defaultSopsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Override default SOPS file path";
    };
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      age
      sops
      ssh-to-age
    ];

    sops = {
      defaultSopsFile = 
        if cfg.defaultSopsFile != null 
        then cfg.defaultSopsFile 
        else lib.snowfall.fs.get-file "secrets/sab/default.yaml";
      age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    };
  };
}