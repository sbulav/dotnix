{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.system.nix;
in
{
  options.system.nix = with types; {
    enable = mkBoolOpt false "Whether to configure Determinate Nix integration.";
    trustedUsers = mkOpt (listOf str) [
      "root"
      "sab"
    ] "Users trusted by the Determinate Nix daemon.";
  };

  config = mkIf cfg.enable {
    determinateNix.customSettings = {
      builders-use-substitutes = true;
      trusted-users = cfg.trustedUsers;
      warn-dirty = false;
    };

    environment.systemPackages = with pkgs; [
      cachix
      nixfmt
      nvd
    ];
  };
}
