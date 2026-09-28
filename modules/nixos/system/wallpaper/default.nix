{
  inputs,
  pkgs,
  config,
  lib,
  ...
}:
with lib;
with lib.custom;
{
  options.system.wallpaper = mkOption {
    type = types.oneOf [
      types.package
      types.path
      types.str
    ];
    default = inputs.wallpapers-nix.packages.${pkgs.stdenv.hostPlatform.system}.catppuccin;
    description = "The wallpaper to use.";
  };
}
