{
  config,
  lib,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.system.security;
in
{
  options.system.security.enable = mkBoolOpt false "Whether to configure the macOS security baseline.";

  config = mkIf cfg.enable {
    networking.applicationFirewall = {
      enable = true;
      blockAllIncoming = false;
      allowSigned = true;
      allowSignedApp = true;
      enableStealthMode = true;
    };

    security = {
      pam.services.sudo_local.touchIdAuth = true;

      sudo.extraConfig = ''
        ${config.custom.user.name} ALL=(ALL:ALL) NOPASSWD: /run/current-system/sw/bin/darwin-rebuild
      '';
    };
  };
}
