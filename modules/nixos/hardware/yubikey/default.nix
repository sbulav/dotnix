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
  cfg = config.hardware.yubikey;
in
{
  options.hardware.yubikey = with types; {
    enable = mkBoolOpt false "Whether or not to enable yubikey support.";
  };

  config = mkIf cfg.enable {
    security.pam.services = {
      login.u2fAuth = true;
      sudo.u2fAuth = true;
    };
    environment.systemPackages = with pkgs; [
      # Yubico's official tools
      yubikey-manager # cli
      # FIXME: insecure
      # yubikey-manager-qt # gui
      yubikey-personalization # cli
      yubico-piv-tool # cli
      yubioath-flutter # gui
      # reload-yubikey
    ];
  };
}
