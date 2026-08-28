# AGENTS.md — NixOS / nix-darwin configuration (Snowfall Lib)

Snowfall Lib flake, namespace `custom`. This file carries only what the tree
does not confess: unwritten conventions, gotchas, and guardrails. Layout facts
live in the filesystem; input facts live in `flake.nix` — look there, they
cannot go stale.

## Discovery

Snowfall auto-discovers by path — creating the file wires it up, there are no
import lists:

- Modules: `modules/{nixos,darwin,home,shared}/{category}/{name}/default.nix`
- Systems: `systems/{arch}/{hostname}/default.nix` — hosts: `nz`, `zanoza`, `mz`, `beez` (NixOS), `mba13` (Darwin)
- Homes: `homes/{arch}/{user}@{hostname}/default.nix`
- Packages: `packages/{name}/default.nix` → `pkgs.custom.{name}`
- Overlays: `overlays/{name}/default.nix` → applied to every system

Reach everything through the namespace: `config.custom.*`, `pkgs.custom.*`,
`lib.custom.*`. `lib.snowfall.fs.get-file "path"` resolves a path relative to
the flake root.

## Gotchas

- `nixpkgs` is pinned to `nixos-26.05` (stable); `nixos-unstable` is exposed as `pkgs.unstable` via overlay in `flake.nix`.
- `determinate.nixosModules.default` and the sops-nix modules are auto-imported into every system and home — never import them by hand.
- `modules/_darwin-disabled/` and `.disabled/` are preserved-but-dead trees: editing them has no effect on any build. The live Darwin host is `mba13`.
- CI (`.github/workflows/cachix.yaml`) builds the flake on every push; Renovate bumps inputs in PRs.

## Decisions

- **Flake-provided home-manager modules are imported unconditionally, never gated on platform** — `pkgs` in HM `imports` (or shaping config attr names, e.g. `optionalAttrs pkgs.stdenv.isLinux` around a config block) is infinite recursion, so `isLinux`-gating an upstream import cannot work. Inertness on other platforms comes from the module's lazy option defaults instead — verify by evaluating the Darwin host's drvPath. (#37)

- **noctalia's sidecar outranks the Nix config, so Nix-owned tables are pruned on activation** — `~/.config/noctalia/config.toml` (read-only store symlink) is deep-merged *under* `~/.local/state/noctalia/settings.toml`, which the settings GUI writes and which survives reboots. Editing a table in Nix that has ever been touched in the GUI therefore looks like a no-op. The split: Nix owns `bar` and `widget` (an activation script drops just those two from the sidecar every rebuild); the GUI owns `theme`, `wallpaper.*`, `lockscreen_widgets`, `location` — never prune those, `wallpaper.last`/`wallpaper.monitors.*` are the seed the wallpaper-derived palette is computed from. One key is carved back out of a Nix-owned table by the script's `KEEP` list: `bar.main.background_opacity`, because `BarConfig` has no background *colour* (the fill is always the theme surface role) and there is no light/dark variant of `[bar.main]` — so one Nix value cannot be legible in both theme modes, and only the GUI knows which mode is live. (#37)

## Commands

Daily driver is the `sys` wrapper (`packages/sys/default.nix`):

- `sys r|rebuild [flake]` — `nixos-rebuild switch` (`darwin-rebuild` on macOS)
- `sys t|test [flake]` — `nixos-rebuild test --fast` (ephemeral, no bootloader update)
- `sys u|update [input]` — update all flake inputs or one
- `sys c|clean` — `nix store optimise && nix store gc`

Raw equivalents:

- Build a host: `nix build .#nixosConfigurations.{hostname}.config.system.build.toplevel` (`darwinConfigurations.mba13` for Darwin)
- Deploy to a remote host: `nix run nixpkgs#deploy-rs -- .#{hostname}` — deploy-rs nodes are auto-derived from `nixosConfigurations` by `lib.custom.mkDeploy` (the flake exposes the raw `deploy` output, not an app)
- Format: `nix fmt` · Validate all configurations: `nix flake check`

**Guardrail: always ask the user before any switch or test** (`sys rebuild`,
`sys test`, `nixos-rebuild switch/test`). Building is always safe.

## Definition of done

1. `nix fmt` — clean.
2. `nix build .#nixosConfigurations.{affected-host}.config.system.build.toplevel` — builds without error, for every host the change touches.
3. `nix flake check` when the change spans hosts or shared modules.
4. Activation (`sys test`, then `sys rebuild`) — only with the user's explicit go-ahead; remote hosts build locally first, then `nix run nixpkgs#deploy-rs -- .#{hostname}`.

## Module conventions

Canonical module shape — the convention across `system.*`, `hardware.*`,
`services.*`, `suites.*`, and most home modules. Match the surrounding files
rather than fighting it (yes, including the double `with`):

```nix
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.<namespace>.<module>;
in {
  options.<namespace>.<module> = {
    enable = mkBoolOpt false "Whether to enable <feature>";
  };

  config = mkIf cfg.enable {
    # implementation
  };
}
```

`lib.custom` helpers (`lib/module/default.nix`):

- `mkOpt type default description` / `mkOpt' type default`
- `mkBoolOpt default description` / `mkBoolOpt' default`
- `enabled` / `disabled` — shorthand for `{ enable = true; }` / `{ enable = false; }`
- `mkDeploy`, `isDarwin` (`lib/deploy/default.nix`)

### Namespaces — two conventions coexist

Match the surrounding modules in the same directory rather than forcing
everything under `custom.*`.

**A. Snowfall system-level categories (no `custom` prefix)** — thin wrappers
over upstream NixOS / home-manager option groups, configuring the host itself:

- `system.*` — `nix`, `fonts`, `locale`, `time`, `xkb`, `security.{doas,sudo,gpg}`
- `hardware.*` — `audio`, `gpu.*`, `networking`, `printing`, `cpu.*`
- `services.*` — `ssh`, `logrotate`, `prometheus-exporters`, `nix-cache-builder`
- `suites.*` — `common`, `desktop`, `develop`, `games`, `server`

**B. `custom.*` categories** — opinionated, repo-specific user features,
especially in home-manager:

- `custom.tools.*` (CLI tools) · `custom.cli-apps.*` (interactive CLI, e.g. `neovim`) · `custom.apps.*` (GUI) · `custom.games.*`
- `custom.desktop.*` (incl. nested `addons`) · `custom.theme.*`
- `custom.security.*` (incl. shared `custom.security.sops`) · `custom.user.*`
- `custom.virtualisation.*` · `custom.containers.*` · `custom.monitoring.*` · `custom.host.*`
- `custom.ai.*` — `claude`, `opencode`, `mcp-k8s-go`, `mcp-grafana`, plus `shared`

### Conventions that earn their line

- Enable a suite before hand-picking modules; suites bundle the related set (see `modules/nixos/suites/`).
- `mkDefault` on values a host should be able to override.
- Home modules needing OS context take an `osConfig ? {}` parameter.
- Darwin-specific behaviour lives in `modules/darwin/`; portable user config in `modules/home/`, branching on `pkgs.stdenv.isLinux` / `isDarwin`.
- For the shape of a host or home file, read an existing one (e.g. `systems/x86_64-linux/mz/default.nix`, `homes/x86_64-linux/sab@mz/default.nix`).

## Secrets (SOPS)

Commit only encrypted files under `secrets/` — keys, tokens, and passwords go
through SOPS, never plaintext into git.

System secrets (`secrets/{hostname}/default.yaml`):

```nix
custom.security.sops = {
  enable = true;
  sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  defaultSopsFile = lib.snowfall.fs.get-file "secrets/{hostname}/default.yaml";
};
```

Home Manager secrets (`secrets/{hostname}@{user}/default.yaml`):

```nix
sops = {
  age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
  defaultSopsFile = lib.snowfall.fs.get-file "secrets/{hostname}@{user}/default.yaml";
};
```

## stateVersion

`system.stateVersion` / `home.stateVersion` record the install-time state of
each host and home. Leave them exactly as found, in every file, always.

## References

- [Snowfall Lib](https://snowfall.org/guides/lib/) · [NixOS Manual](https://nixos.org/manual/nixos/stable/) · [Home Manager](https://nix-community.github.io/home-manager/) · [nix-darwin](https://daiderd.com/nix-darwin/manual/index.html) · [sops-nix](https://github.com/Mic92/sops-nix)
