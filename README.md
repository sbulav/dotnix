# My configuration files managed with NixOS flake

[![Nix](https://img.shields.io/badge/NIX-5277C3.svg?style=for-the-badge&logo=NixOS&logoColor=white)](https://builtwithnix.org/)
[![NixOS](https://img.shields.io/badge/NIXOS-5277C3.svg?style=for-the-badge&logo=NixOS&logoColor=white)](https://nixos.org/)
[![Snowfall](https://img.shields.io/static/v1?logoColor=d8dee9&label=Built%20With&labelColor=5e81ac&message=Snowfall&color=d8dee9&style=for-the-badge)](https://github.com/snowfallorg/lib)
[![Check flake inputs](https://github.com/sbulav/dotnix/actions/workflows/cachix.yaml/badge.svg)](https://github.com/sbulav/dotnix/actions/workflows/cachix.yaml)

## Configuration

This Snowfall Lib flake manages the NixOS hosts `nz`, `mz`, `zanoza`, and
`beez`, plus the Apple Silicon Mac `mba13`. NixOS desktops use Hyprland
with Noctalia. Home Manager provides user configuration on both platforms.

Edit host configuration in `systems/` and user profiles in `homes/`. Reusable
modules live in `modules/`, local packages in `packages/`, and flake checks in
`checks/`. See [AGENTS.md](AGENTS.md) for how to trace a setting and validate
a change.

[CI](.github/workflows/cachix.yaml) checks formatting, runs `statix` and
`deadnix`, builds the flake checks, evaluates every system and home profile,
and builds all five systems from the committed lock file.

## Daily use

The [`sys` wrapper](packages/sys/default.nix) uses `SYS_FLAKE` or the nearest
enclosing `flake.nix`. `sys rebuild [flake]` switches the system.
On NixOS, `sys test [flake]` activates a configuration for the current boot.
Use `sys update nixpkgs` to update just the `nixpkgs` input.

## Runbooks

- [Verify YubiKey GPG signing and fallback](docs/yubikey-gpg-setup.md)
- [Manage SOPS secrets](modules/shared/security/sops/README.md)
- [Replace a Zanoza disk](docs/zanoza-disk-replacement.md)
- [Operate monitoring on Beez](docs/monitoring-migration.md)

## Credits

Kudos for config inspiration to:

- [Introduction to Nix & NixOS](https://nixos-and-flakes.thiscute.world/introduction/)
- [Nix for MacOS by dustinlyons](https://github.com/dustinlyons/nixos-config)
- [Nix starter configs by Misterio77](https://github.com/Misterio76/nix-starter-configs)
- [Nix configs with snowlake by Jake Hamilton](https://github.com/jakehamilton/config)

You might also want to check out my blog with [#Nix category](https://sbulav.github.io/categories/#nix)
