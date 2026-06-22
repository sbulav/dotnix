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
      extra-substituters = [ "https://dotnix.cachix.org?priority=10" ];
      extra-trusted-public-keys = [
        "dotnix.cachix.org-1:/T5Rhb8DkIIAU5wwL2YnMqMsNUkIcOxCIaHUKSaLAVs="
      ];
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
