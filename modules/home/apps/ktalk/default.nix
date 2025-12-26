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
      example = "pkgs.${namespace}.ktalk-nvidia";
      description = ''
        The Ktalk package to install.

        You can override this to use a custom or NVIDIA‑enabled version,
        for example:
        ```
        custom.apps.ktalk.package = pkgs.${namespace}.ktalk-nvidia;
        ```
      '';
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];
  };
}
