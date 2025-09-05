# DEPRECATED: This module has been replaced by the shared SOPS module
# Minimal stub for backwards compatibility
{
  lib,
  namespace,
  ...
}: 
with lib.custom; {
  # Minimal options to prevent errors
  options.${namespace}.security.sops = {
    enable = lib.mkEnableOption "SOPS secrets management (deprecated stub)";
    secrets = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Secret definitions (deprecated stub)";
    };
  };

  config = {
    # Add deprecation warning
    warnings = lib.mkIf true [
      "modules/home/security/sops is deprecated - configurations now use the shared SOPS module at modules/shared/security/sops"
    ];
  };
}
