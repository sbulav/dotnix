{
  options,
  config,
  pkgs,
  lib,
  ...
}:
with lib;
with lib.custom; let
  cfg = config.custom.nix;
  users = ["root" config.custom.user.name];
  substitutersList = [
    "https://cache.nixos.org"
    "https://nix-community.cachix.org"
    "https://dotnix.cachix.org"
    "https://nixpkgs-unfree.cachix.org"
    "https://numtide.cachix.org"
    "https://wezterm.cachix.org"
  ];

  trustedKeysList = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "dotnix.cachix.org-1:/T5Rhb8DkIIAU5wwL2YnMqMsNUkIcOxCIaHUKSaLAVs="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs="
    "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
    "wezterm.cachix.org-1:kAbhjYUC9qvblTE+s7S+kl5XM1zVa4skO+E/1IDWdH0="
  ];
  join = lib.concatStringsSep " ";
in {
  options.custom.nix = with types; {
    enable = mkBoolOpt true "Whether or not to manage nix configuration.";
    # Unused when nix.enable = false, but kept for interface compatibility
    package = mkOpt package pkgs.nixVersions.latest "Which nix package to use.";
  };

  config = mkIf cfg.enable {
    #############################################
    # Let Determinate manage the Nix installation
    #############################################
    nix.enable = false;

    #############################################
    # Developer tools
    #############################################
    environment.systemPackages = with pkgs; [
      cachix
      deploy-rs
      nix-index
      nix-prefetch-git
      nixfmt-rfc-style
      nvd
    ];

    #############################################
    # Determinate Nix user config
    # (picked up via /etc/nix/nix.custom.conf)
    #############################################

    environment.etc."nix/nix.custom.conf".text = ''
      experimental-features = nix-command flakes
      http-connections = 50
      warn-dirty = false
      log-lines = 50
      builders-use-substitutes = true

      # Darwin historical quirks you noted:
      sandbox = false
      auto-optimise-store = false

      allow-import-from-derivation = true

      trusted-users = ${join users}
      allowed-users = ${join users}

      extra-nix-path = nixpkgs=flake:nixpkgs
      build-users-group = nixbld

      substituters = ${join substitutersList}
      trusted-public-keys = ${join trustedKeysList}
    '';

    #############################################
    # Weekly GC via a LaunchAgent (no 'enable' key)
    #############################################
    launchd.user.agents."nix-gc" = {
      serviceConfig = {
        ProgramArguments = [
          "${pkgs.nix}/bin/nix-collect-garbage"
          "--delete-older-than"
          "30d"
        ];
        # Sunday 03:00
        StartCalendarInterval = {
          Weekday = 0;
          Hour = 3;
          Minute = 0;
        };
        StandardOutPath = "/tmp/nix-gc.log";
        StandardErrorPath = "/tmp/nix-gc.err";
        KeepAlive = false;
        RunAtLoad = false;
      };
    };

    #############################################
    # Activation: diff using the nix actually on PATH
    #############################################
    system.activationScripts.postActivation =
      {
        text = ''
          NIX_BIN_DIR="$(dirname "$(command -v nix)")"
          ${pkgs.nvd}/bin/nvd --nix-bin-dir="$NIX_BIN_DIR" diff /run/current-system "$systemConfig" || true
        '';
      }
      // lib.optionalAttrs pkgs.stdenv.isLinux {
        supportsDryActivation = true;
      };
  };
}
