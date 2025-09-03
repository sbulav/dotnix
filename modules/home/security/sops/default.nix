# DEPRECATED: This module has been replaced by the shared SOPS module
# Redirect to shared module for backwards compatibility
{
  lib,
  ...
}: {
  # Import the shared SOPS module
  imports = [
    ../../../shared/security/sops
  ];

  # Add deprecation warning
  warnings = [
    "modules/home/security/sops is deprecated - configurations now use the shared SOPS module at modules/shared/security/sops"
  ];
}
