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
    enable = mkBoolOpt false "Whether to manage the Nix installation and its settings.";
    trustedUsers = mkOpt (listOf str) [
      "root"
      "sab"
    ] "Users trusted by the Nix daemon.";
  };

  config = mkIf cfg.enable {
    nix = {
      settings = {
        builders-use-substitutes = true;
        experimental-features = "nix-command flakes";
        substituters = [
          "http://beez.sbulav.ru:5000?priority=10" # local nix-cache-builder (serves shared FODs to darwin too)
          "https://dotnix.cachix.org?priority=10"
          "https://cache.nixos.org?priority=20"
        ];
        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "beez.sbulav.ru:g3AGSm7ZgXhEvJCO/z7TPsykfj/F+aHGO4h7QcUGTD8="
          "dotnix.cachix.org-1:/T5Rhb8DkIIAU5wwL2YnMqMsNUkIcOxCIaHUKSaLAVs="
        ];
        trusted-users = cfg.trustedUsers;
        warn-dirty = false;
      };

      gc = {
        automatic = true;
        options = "--delete-older-than 7d";
      };
      # auto-optimise-store corrupts the store on macOS; nix-darwin asserts against it.
      optimise.automatic = true;

      # flake-utils-plus registry setup, as on NixOS
      generateRegistryFromInputs = true;
      generateNixPathFromInputs = true;
      linkInputs = true;
    };

    # Runs before nix-darwin's own Determinate check, whose advice
    # (nix.enable = false) would undo the move to upstream Nix.
    system.checks.text = mkBefore ''
      if [[ -e /usr/local/bin/determinate-nixd ]]; then
        printf >&2 '\e[1;31merror: Determinate Nix is still installed, aborting activation\e[0m\n'
        printf >&2 'This configuration runs upstream Nix. Migrate first: docs/mac-upstream-nix.md\n'
        exit 2
      fi
    '';

    environment.systemPackages = with pkgs; [
      cachix
      nixfmt
      nvd
    ];
  };
}
