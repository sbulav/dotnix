{
  options,
  config,
  pkgs,
  lib,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.hardware.fingerprint;
in
{
  options.hardware.fingerprint = with types; {
    enable = mkBoolOpt false "Whether or not to enable fingerprint support.";
  };

  config = mkIf cfg.enable {
    services.fprintd.enable = true;

    # NixOS automatically enables fprintAuth for all PAM services when fprintd is enabled
    # This includes swaylock, login, sudo, and other PAM services
    #
    # Authentication order (handled by NixOS module ordering):
    # 1. YubiKey (U2F) - order 10900 (if hardware.yubikey.enable = true)
    # 2. Fingerprint - order 11400 (this module)
    # 3. Password - order 12900 (always available)
    #
    # No manual PAM configuration needed - NixOS handles the ordering automatically
  };
}
