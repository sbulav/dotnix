{
  description = "Sbulav nix config";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    stable.url = "github:nixos/nixpkgs/nixos-25.05";

    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";

    snowfall-lib = {
      url = "github:snowfallorg/lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-homebrew = {
      url = "github:zhaofengli-wip/nix-homebrew";
    };
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };

    # Home manager
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    wallpapers-nix = {
      url = "github:sbulav/wallpapers-nix";
    };

    # Sops (Secrets)
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "stable";
    };

    sops-nix-darwin = {
      url = "github:Mic92/sops-nix/nix-darwin";
      # url = "github:khaneliman/sops-nix/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # System Deployment
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Stylix (Theme Management)
    stylix = {
      url = "github:danth/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs: let
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

      overlays = with inputs; [];

      homes.modules = with inputs; [
        sops-nix.homeManagerModules.sops
        stylix.homeManagerModules.stylix
        ./modules/shared/security/sops
        # Disable home-manager's built-in opencode module and provide a stub
        ({lib, ...}: {
          disabledModules = [ "programs/opencode.nix" ];
          options.programs.opencode = lib.mkOption {
            type = lib.types.attrs;
            default = {};
            description = "Stub for opencode - use custom.ai.opencode instead";
          };
        })
      ];
      systems = {
        modules = {
          darwin = with inputs; [
            sops-nix-darwin.darwinModules.sops
            stylix.darwinModules.stylix
            ./modules/shared/desktop/stylix
          ];
          nixos = with inputs; [
            sops-nix.nixosModules.sops
            determinate.nixosModules.default
            stylix.nixosModules.stylix
            ./modules/shared/desktop/stylix
          ];
        };
      };
      deploy = lib.mkDeploy {inherit (inputs) self;};
    };
}
