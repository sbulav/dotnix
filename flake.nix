{
  description = "Sbulav nix config";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

    unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    # Every flakehub.com URL in Determinate's input tree is replaced with its
    # GitHub equivalent. `nix` must be the nix-src release matching the
    # determinate tag (determinate-nixd takes its version from it), so bump
    # both tags together — Renovate's lock file maintenance cannot move them.
    determinate = {
      url = "github:DeterminateSystems/determinate/v3.22.5";
      inputs.nix.url = "github:DeterminateSystems/nix-src/v3.22.5";
      inputs.nix.inputs.flake-parts.url =
        "github:hercules-ci/flake-parts/49f0870db23e8c1ca0b5259734a02cd9e1e371a1";
      inputs.nix.inputs.git-hooks-nix.url =
        "github:cachix/git-hooks.nix/80479b6ec16fefd9c1db3ea13aeb038c60530f46";
      inputs.nix.inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    snowfall-lib = {
      # Maintained Snowfall fork with current Nix compatibility fixes and
      # correct namespace/Home Manager argument propagation.
      url = "github:anntnzrb/snowfall-lib";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.darwin.follows = "darwin";
      inputs.home-manager.follows = "home-manager";
    };

    darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home manager
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Pre-built nix-index database (weekly) for comma + command-not-found
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    wallpapers-nix = {
      url = "github:sbulav/wallpapers-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Lian Li Galahad II LCD pump control (glc), used by the galahad-lcd
    # home addon on mz.
    galahad-linux-control = {
      url = "github:sbulav/galahad-linux-control";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Woomer: Wayland zoomer (personal fork with HiDPI/scaling fixes).
    # Intentionally NOT following our nixpkgs: woomer pins its own
    # nixpkgs-unstable + crane for the raylib/bindgen build.
    woomer.url = "github:sbulav/woomer";

    # Herdr: terminal multiplexer for AI coding agents.
    herdr = {
      url = "github:herdrdev/herdr/v0.9.3";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Herdr-remote relay + web app with native session lifecycle and
    # structured Claude Code/OpenCode output. Plain source repo (not a flake);
    # packaged in packages/herdr-relay and served by the home module.
    herdr-remote = {
      url = "github:sbulav/herdr-relay";
      flake = false;
    };

    # Noctalia v5 desktop shell (issue #37, mz trial). Pinned to the `cachix`
    # branch: CI pushes main there only after the build is in the official
    # cachix, so every pin has cache hits. Intentionally NOT following our
    # nixpkgs — a follows override changes every derivation hash and kills
    # those cache hits (nixpkgs' own noctalia-shell is the dead quickshell v4).
    noctalia.url = "github:noctalia-dev/noctalia/cachix";

    # Sops (Secrets)
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # System Deployment
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    let
      lib = inputs.snowfall-lib.mkLib {
        inherit inputs;
        src = ./.;

        snowfall = {
          meta = {
            name = "dotfiles";
            title = "dotfiles";
          };

          namespace = "custom";
        };
      };
    in
    lib.mkFlake {
      inherit inputs;
      src = ./.;

      channels-config = {
        allowUnfree = true;
        # allowBroken = true;
      };

      outputs-builder = channels: {
        formatter = channels.nixpkgs.nixfmt-tree;
      };

      overlays = with inputs; [
        # Expose unstable packages via pkgs.unstable
        (final: _prev: {
          unstable = import unstable {
            system = final.stdenv.hostPlatform.system;
            config.allowUnfree = true;
          };
        })
      ];

      homes.modules = with inputs; [
        sops-nix.homeManagerModules.sops
        ./modules/shared/security/sops
      ];
      systems = {
        modules = {
          darwin = with inputs; [
            determinate.darwinModules.default
            sops-nix.darwinModules.default
          ];
          nixos = with inputs; [
            sops-nix.nixosModules.sops
            determinate.nixosModules.default
            nix-index-database.nixosModules.nix-index
          ];
        };
      };
      deploy = lib.mkDeploy { inherit (inputs) self; };
    };
}
