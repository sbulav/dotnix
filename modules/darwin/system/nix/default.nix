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
  options.system.nix = {
    enable = mkBoolOpt false "Whether to manage the Nix installation and its settings.";
  };

  # nix-darwin already adds cache.nixos.org (substituter and key) and root to
  # trusted-users, and flake-utils-plus adds extra-experimental-features =
  # nix-command flakes; repeating them here only duplicates them in nix.conf.
  config = mkIf cfg.enable {
    nix = {
      settings = {
        builders-use-substitutes = true;
        substituters = [
          "http://beez.sbulav.ru:5000?priority=10" # local nix-cache-builder (serves shared FODs to darwin too)
          "https://dotnix.cachix.org?priority=10"
        ];
        trusted-public-keys = [
          "beez.sbulav.ru:g3AGSm7ZgXhEvJCO/z7TPsykfj/F+aHGO4h7QcUGTD8="
          "dotnix.cachix.org-1:/T5Rhb8DkIIAU5wwL2YnMqMsNUkIcOxCIaHUKSaLAVs="
        ];
        trusted-users = [ config.custom.user.name ];
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

    environment.systemPackages = with pkgs; [
      cachix
      nixfmt
      nvd
    ];
  };
}
