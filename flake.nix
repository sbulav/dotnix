{
  description = "Sbulav nix config";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

    unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    determinate = {
      url = "github:DeterminateSystems/determinate/v3.19.1";
      inputs.nix.url = "github:NixOS/nix/35185ec4d4dcdfe34e08f0e48f6a66afd3b95007";
      inputs.nix.inputs.flake-parts.url =
        "github:hercules-ci/flake-parts/49f0870db23e8c1ca0b5259734a02cd9e1e371a1";
      inputs.nix.inputs.git-hooks-nix.url =
        "github:cachix/git-hooks.nix/80479b6ec16fefd9c1db3ea13aeb038c60530f46";
      inputs.nix.inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    snowfall-lib = {
      url = "github:snowfallorg/lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Darwin inputs (disabled - no Darwin systems in use)
    # darwin = {
    #   url = "github:nix-darwin/nix-darwin";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    # nix-homebrew = {
    #   url = "github:zhaofengli-wip/nix-homebrew";
    # };
    # homebrew-core = {
    #   url = "github:homebrew/homebrew-core";
    #   flake = false;
    # };
    # homebrew-cask = {
    #   url = "github:homebrew/homebrew-cask";
    #   flake = false;
    # };

    # Home manager
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    wallpapers-nix = {
      url = "github:sbulav/wallpapers-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    whisper-dictation = {
      url = "github:jacopone/whisper-dictation";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Woomer: Wayland zoomer (personal fork with HiDPI/scaling fixes).
    # Intentionally NOT following our nixpkgs: woomer pins its own
    # nixpkgs-unstable + crane for the raylib/bindgen build.
    woomer.url = "github:sbulav/woomer";

    # Sops (Secrets)
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # sops-nix-darwin = {
    #   url = "github:Mic92/sops-nix/nix-darwin";
    #   # url = "github:khaneliman/sops-nix/nix-darwin";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

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

          # Disabled Darwin systems/homes live under `.disabled/` so snowfall
          # doesn't scan them (it identifies darwin by `hasInfix "darwin"` on
          # the directory name and tries to build a darwinSystem otherwise).
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

      overlays = with inputs; [
        # Expose unstable packages via pkgs.unstable
        (final: prev: {
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
          # darwin = with inputs; [ sops-nix-darwin.darwinModules.sops ]; # Disabled - no Darwin systems
          nixos = with inputs; [
            sops-nix.nixosModules.sops
            determinate.nixosModules.default
          ];
        };
      };
      deploy = lib.mkDeploy { inherit (inputs) self; };
    };
}
