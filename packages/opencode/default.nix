# Rebuilding fast-paced package without bumping all flakes
# Source: https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/op/opencode/package.nix#L182
# packages/opencode/default.nix
{pkgs}: let
  lib = pkgs.lib;

  # Compat: try the function wherever nixpkgs exposes it
  updateSourceVersion =
    lib.sources.updateVersion
    or lib.sources.updateSourceVersion
    or lib.updateSourceVersion
    or (drv: updates: drv // updates); # last resort (will only change attrs, not src)
in
  pkgs.opencode.overrideAttrs (
    old:
      updateSourceVersion old {
        # bump just these; everything else stays the same
        version = "0.7.3";
        hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
        # If the package uses cargo/vendor, uncomment and set too:
        # cargoHash = "sha256-…";
        # vendorHash = "sha256-…";
      }
  )
