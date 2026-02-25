{
  description = "Sbulav nix config";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

    unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";

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
      url = "github:nix-community/home-manager/release-25.11";
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

          # Skip Darwin discovery to speed up evaluation
          systems.exclude = [ "darwin" ];
          homes.exclude = [ "darwin" ];
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
