# AGENTS.md — dotnix

Snowfall Lib flake with namespace `custom`.

## Start here

1. For a host change, find its profile with `rg --files systems homes -g default.nix`.
   Read the matching system or user profile and follow the suite or option it sets.
2. Find the option in the relevant `modules/nixos/`, `modules/darwin/`, or
   `modules/home/` subtree. Use `rg -l` to narrow the file list, then
   `rg -n -C 3` for the relevant definitions and callers. Read the owning
   module, files it references, and a matching check in `checks/` as needed.
3. Stop discovery once you know what sets the option, where it is implemented,
   and which configurations it affects. Use Nix evaluation if suite defaults
   or overrides make the effective value unclear.

Use `flake.nix` for input sources and wiring. Inspect `flake.lock` for input
pins, `docs/` for a named runbook or research note, `secrets/` for secret
changes, and `modules/home/ai/` for agent tooling changes.

## Discovery and conventions

- Snowfall discovers `default.nix` recursively under the NixOS, Darwin, and
  Home Manager module trees. It also discovers systems, homes, packages,
  checks, and shells by path. Local packages appear at `pkgs.custom.<name>`.
- Match nearby module namespaces. System wrappers commonly use `system.*`,
  `hardware.*`, `services.*`, or `suites.*`. Repo-specific features commonly
  use `custom.*`. Prefer enabling a suite before selecting individual modules.
- Follow the local `cfg`, `mkIf cfg.enable`, and `lib.custom` conventions.
  Helpers live in `lib/module/default.nix`. Use `mkDefault` where profiles
  should be able to override values.
- Put Darwin-specific behavior under `modules/darwin/` and portable user
  behavior under `modules/home/`. Home modules needing OS context take
  `osConfig ? {}`. Use `lib.snowfall.fs.get-file` for flake-root-relative paths.
- Agent skills live in `modules/home/ai/shared/skill/` and
  `modules/home/ai/shared/workflow/skill/`. Claude Code, OpenCode, and Codex
  render them through `shared/registry.nix`. OpenCode agents live in
  `modules/home/ai/opencode/agent/`. Use `writing-for-agents` for these edits
  or changes to `AGENTS.md`.
- For module or host retirement, follow [the lifecycle policy](docs/module-lifecycle.md).
  Git history holds retired configurations.

## Decisions

- Import flake-provided Home Manager modules unconditionally. Inspecting
  `pkgs` in `imports` or using it to choose config attribute names recurses.
  Use lazy option defaults or `mkIf` for platform-specific behavior. Evaluate
  the Darwin host's `drvPath` after changes to shared Home Manager imports.
- When changing Noctalia settings ownership, read `pruneTables` and `KEEP`
  in [the Noctalia module](modules/home/desktop/addons/noctalia/default.nix).
  The GUI sidecar takes precedence over the Nix config.
- For secrets, follow [the SOPS guide](modules/shared/security/sops/README.md)
  and commit only encrypted material. The flake imports upstream sops-nix for
  systems and homes, and imports `modules/shared/security/sops` for homes.
  Use these imports as provided.
- Preserve every `system.stateVersion` and `home.stateVersion`.

## Validation and activation

1. Run `nix fmt -- --ci`, `nix develop --no-write-lock-file -c statix check .`,
   and `nix develop --no-write-lock-file -c deadnix --fail --no-lambda-pattern-names -- .`.
2. Build each affected host with
   `nix build --no-link .#nixosConfigurations.<host>.config.system.build.toplevel`.
   Use `darwinConfigurations.mba13` for Darwin. Run `nix flake check` for
   cross-host or shared module changes. [CI](.github/workflows/cachix.yaml)
   runs the checks and builds all live hosts.
3. **Get explicit user approval before any switch, test activation, or
   deployment.** Use `sys test` then `sys rebuild` for local NixOS activation.
   For remote hosts, build locally first and then use
   `nix run nixpkgs#deploy-rs -- .#<host>`. The flake exposes `deploy` nodes
   via `lib.custom.mkDeploy`.
