# My configuration files managed with NixOS flake

[![Nix](https://img.shields.io/badge/NIX-5277C3.svg?style=for-the-badge&logo=NixOS&logoColor=white)](https://builtwithnix.org/)
[![NixOS](https://img.shields.io/badge/NIXOS-5277C3.svg?style=for-the-badge&logo=NixOS&logoColor=white)](https://nixos.org/)
[![Snowfall](https://img.shields.io/static/v1?logoColor=d8dee9&label=Built%20With&labelColor=5e81ac&message=Snowfall&color=d8dee9&style=for-the-badge)](https://github.com/snowfallorg/lib)
[![Check flake inputs](https://github.com/sbulav/dotnix/actions/workflows/cachix.yml/badge.svg)](https://github.com/sbulav/dotnix/actions/workflows/cachix.yml)

## Nix

- MacOS
  - [Nix Flakes](https://nixos.wiki/wiki/Flakes)
  - [Nix-Darwin](https://github.com/LnL7/nix-darwin)
  - [Home-Manager](https://nix-community.github.io/home-manager/)
- NixOS
  - [Nix Flakes](https://nixos.wiki/wiki/Flakes)
  - [Home-Manager](https://nix-community.github.io/home-manager/)
  - [Hyprland](https://wiki.hyprland.org) + Waybar, Swaylock, Rofi, mako, hyprpaper

Nix flakes following arbitrary Snowfall lib conventions:

```text
nix/
│
│ Nix flake.
├─ flake.nix
│
│ An optional custom library.
├─ lib/
│
│ An optional set of packages to export.
├─ packages/
│
├─ modules/ (optional modules)
│
├─ overlays/ (optional overlays)
│
├─ systems/ (optional system configurations)
│
└─ homes/ (optional homes configurations)
```

Kudos for config inspiration to:

- [Introduction to Nix & NixOS](https://nixos-and-flakes.thiscute.world/introduction/)
- [Nix for MacOS by dustinlyons](https://github.com/dustinlyons/nixos-config)
- [Nix starter configs by Misterio77](https://github.com/Misterio76/nix-starter-configs)
- [Nix configs with snowlake by Jake Hamilton](https://github.com/jakehamilton/config)

You might also want to check out my blog with [#Nix category](https://sbulav.github.io/categories/#nix)

### Useful NIX commands

Quickly try out new package in the shell without installing it:

```sh
nix shell nixpkgs#glow
```

List all generations:

```sh
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
```

Rollback to previous generation:

```sh
sudo nixos-rebuild switch --flake ~/dotnix#nz --rollback
```

Rollback to previous generation:

```sh
sudo nixos-rebuild switch --flake ~/dotnix#nz --rollback
```

Activate specific generation:

```sh
sudo nix-env --profile /nix/var/nix/profiles/system --switch-generation 210
```
