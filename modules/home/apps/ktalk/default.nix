{
  lib,
  config,
  pkgs,
  namespace,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.custom.apps.ktalk;
in
{
  options.custom.apps.ktalk = {
    # Whether to enable Ktalk application
    enable = mkEnableOption "Ktalk (Kontur Talk) desktop client";

    # Allow user to override which package is used
    package = mkOption {
      type = types.package;
      default = pkgs.${namespace}.ktalk;
      description = "The Ktalk package to install.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];
  };
}
