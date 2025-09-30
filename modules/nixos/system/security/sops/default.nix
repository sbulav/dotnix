# DEPRECATED: This module has been replaced by the shared SOPS module
# System-level compatibility layer that only emits a warning when enabled.
{
  config,
  lib,
  namespace ? "custom",
  ...
}: let
  inherit (lib) attrByPath mkIf;

  cfg = attrByPath [namespace "security" "sops"] {enable = false;} config;
in {
  config = mkIf cfg.enable {
    warnings = [
      "modules/nixos/system/security/sops is deprecated - use shared SOPS patterns in system configurations"
    ];
  };
}
