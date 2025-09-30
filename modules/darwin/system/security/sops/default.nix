# DEPRECATED: This module has been replaced by the shared SOPS module
# Keep it around to surface a warning for older configurations that still
# reference it explicitly.
{
  config,
  lib,
  ...
}: let
  inherit (lib) attrByPath mkIf;

  cfg = attrByPath ["custom" "security" "sops"] {enable = false;} config;
in {
  config = mkIf cfg.enable {
    warnings = [
      "modules/darwin/system/security/sops is deprecated - use shared SOPS patterns in system configurations"
    ];
  };
}
