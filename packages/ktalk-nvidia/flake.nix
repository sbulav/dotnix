{
  description = "Ktalk with NVIDIA GPU support";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: 
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    packages.${system} = {
      ktalk-nvidia = pkgs.callPackage ./package.nix {};
      default = self.packages.${system}.ktalk-nvidia;
    };

    apps.${system} = {
      ktalk-nvidia = {
        type = "app";
        program = "${self.packages.${system}.ktalk-nvidia}/bin/ktalk-nvidia";
      };
      default = self.apps.${system}.ktalk-nvidia;
    };

    overlays.default = final: prev: {
      ktalk-nvidia = self.packages.${system}.ktalk-nvidia;
    };
  };
}