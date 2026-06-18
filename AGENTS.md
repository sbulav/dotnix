# AGENTS.md - NixOS/Nix-Darwin Configuration

This guide provides comprehensive instructions for AI agents and developers working with this NixOS/nix-darwin configuration managed by Snowfall Lib.

## Project Overview

- **Framework**: Snowfall Lib - provides structured flake organization
- **Namespace**: `custom` - all custom options are under this namespace
- **Module Types**: 
  - `modules/nixos/` - NixOS system modules
  - `modules/darwin/` - nix-darwin system modules  
  - `modules/home/` - Home Manager modules
  - `modules/shared/` - Shared modules across systems
- **Systems**: Defined in `systems/{arch}/{hostname}/default.nix`
- **Homes**: Defined in `homes/{arch}/{user}@{hostname}/default.nix`
- **Channel**: `nixpkgs` is pinned to `nixos-26.05` (stable). `nixos-unstable` is exposed via overlay as `pkgs.unstable`.
- **Darwin status**: active for the Apple Silicon host `mba13`. Historical Darwin modules remain under `modules/_darwin-disabled/`; historical host and home profiles remain under `.disabled/` and are not built.

## Build/Test Commands

### System Operations
- **Build NixOS system**: `nix build .#nixosConfigurations.{hostname}.config.system.build.toplevel`
  - Available hosts: `nz`, `zanoza`, `mz`, `beez`
- **Build Darwin system**: `nix build .#darwinConfigurations.mba13.config.system.build.toplevel`
- **Rebuild NixOS locally**: `sudo nixos-rebuild switch --flake .#{hostname}`
- **Rebuild Darwin locally**: `darwin-rebuild switch --flake .#mba13`
- **Deploy to remote**: `nix run .#deploy.{hostname}` (zanoza, nz, mz, beez — deploy-rs auto-derives from `nixosConfigurations`)

### Workflow Wrapper (`sys`)

`packages/sys/default.nix` builds a `sys` shell wrapper used as the daily driver:

| Command | Action |
|---|---|
| `sys rebuild` / `sys r` | `nixos-rebuild switch --flake .#` (or `darwin-rebuild` on macOS) |
| `sys test` / `sys t` | `nixos-rebuild test --fast --flake .#` (ephemeral, no bootloader update) |
| `sys update` / `sys u` | `nix flake update` |
| `sys clean` / `sys c` | `nix store optimise && nix store gc` |

Caveat: as of writing, the script hardcodes `--flake ~/dotfiles/nix#`. If the checkout lives elsewhere (e.g. `~/dotnix`), invoke the underlying `nixos-rebuild` / `nix` commands directly until the path is fixed.

### Development & Validation
- **Format code**: `nix fmt` (uses nixfmt)
- **Check flake**: `nix flake check` - validates all configurations
- **Update inputs**: `nix flake update` - updates all flake inputs
- **Update specific input**: `nix flake update {input-name}`
- **Test package**: `nix shell nixpkgs#{package}` or `nix shell .#{package}`
- **Build custom package**: `nix build .#sys` (or other packages in packages/)

### Debugging
- **Check option value**: `nixos-option {option.path}`
- **Evaluate expression**: `nix eval .#{path}`
- **Show flake outputs**: `nix flake show`
- **Build with trace**: `nix build --show-trace .#{target}`

## Repository Structure

```
.
├── flake.nix              # Main flake configuration
├── systems/               # System configurations per host
│   ├── x86_64-linux/     # Linux systems
│   └── aarch64-darwin/   # macOS systems
├── homes/                 # Home Manager configurations per user
│   ├── x86_64-linux/
│   └── aarch64-darwin/
├── modules/               # Modular configuration options
│   ├── nixos/            # NixOS-specific modules
│   ├── darwin/           # Darwin-specific modules
│   ├── home/             # Home Manager modules
│   └── shared/           # Cross-platform modules
├── packages/              # Custom package definitions
├── overlays/              # Nixpkgs overlays
├── lib/                   # Custom library functions
│   ├── module/           # Module helpers (mkOpt, mkBoolOpt, etc.)
│   └── deploy/           # Deployment helpers
├── shells/                # Development shells (default, python)
├── secrets/               # SOPS encrypted secrets
├── docs/                  # Manual setup guides (e.g. yubikey-gpg)
├── .github/
│   ├── workflows/cachix.yaml  # CI: builds flake + pushes to cachix
│   └── renovate.json          # Automated dep updates
└── (disabled)             # Preserved-but-inactive Darwin trees:
    modules/_darwin-disabled/
    .disabled/systems-aarch64-darwin/
    .disabled/homes-aarch64-darwin/
```

## Module Development Guidelines

### Module Structure

Every module should follow this pattern:

```nix
{
  config,
  lib,
  pkgs,
  ...
}:
with lib.custom; let
  inherit (lib) mkIf types;
  cfg = config.custom.{category}.{module-name};
in {
  options.custom.{category}.{module-name} = {
    enable = mkBoolOpt false "Whether to enable {feature description}";
    # Additional options...
  };

  config = mkIf cfg.enable {
    # Configuration implementation
  };
}
```

### Custom Library Functions

Available in `lib.custom` (defined in `lib/module/default.nix`):

- `mkOpt type default description` - Create option with type, default, and description
- `mkOpt' type default` - Create option without description (null)
- `mkBoolOpt default description` - Create boolean option
- `mkBoolOpt' default` - Create boolean option without description
- `enabled` - Shorthand for `{ enable = true; }`
- `disabled` - Shorthand for `{ enable = false; }`

Deploy helpers (`lib/deploy/default.nix`, also under `lib.custom.*`):
- `mkDeploy { inherit self; }` - Generates the `deploy.nodes` attrset for deploy-rs from every entry in `nixosConfigurations` (and Darwin configs when re-enabled). Used in `flake.nix`: `deploy = lib.mkDeploy { inherit (inputs) self; }`.
- `isDarwin system` - Predicate used by `mkDeploy` to dispatch profile type.

### Option Namespacing

Two namespace conventions coexist in this repo. Match the surrounding modules in the same directory rather than forcing everything under `custom.*`.

**A. Snowfall system-level categories (no `custom` prefix)** — used by modules that configure the host itself:
- `system.*` — `system.nix`, `system.fonts`, `system.locale`, `system.time`, `system.xkb`, `system.security.{doas,sudo,gpg}`
- `hardware.*` — `hardware.audio`, `hardware.gpu.{nvidia,...}`, `hardware.networking`, `hardware.printing`, `hardware.cpu.*`
- `services.*` — `services.ssh`, `services.logrotate`, `services.prometheus-exporters`, `services.nix-cache-builder`
- `suites.*` — `common`, `desktop`, `develop`, `games`, `server`

**B. `custom.*` user-feature categories** — used for opinionated user-facing features, especially in home-manager:
- `custom.tools.*` — CLI tools and utilities
- `custom.cli-apps.*` — interactive CLI apps (e.g. `neovim`)
- `custom.apps.*` — GUI applications
- `custom.virtualisation.*` — virtualization tooling
- `custom.security.*` — security and secrets (incl. shared `custom.security.sops`)
- `custom.user.*` — user identity / dotfiles
- `custom.containers.*`, `custom.monitoring.*`, `custom.host.*`
- `custom.desktop.*` — incl. nested `addons` (`hyprpaper`, `kitty`, `wallpaper`, …)
- `custom.theme.*`
- `custom.ai.*` — `claude`, `opencode`, `mcp-k8s-go`, `mcp-grafana`, plus `shared`

**Choosing between A and B:** pick (A) when the option is a thin wrapper over an upstream NixOS / home-manager option group; pick (B) for opinionated, repo-specific features.

**Examples:**
```nix
# A — system-level
system.nix.enable = true;
hardware.audio.enable = true;
services.ssh.enable = true;
suites.common.enable = true;

# B — custom.*
custom.tools.http.enable = true;
custom.cli-apps.neovim.enable = true;
custom.security.sops.enable = true;
custom.ai.opencode.enable = true;
```

## Code Style Guidelines

### Library Usage

The dominant pattern in this repo combines both `with` clauses:

```nix
{ config, lib, pkgs, ... }:
with lib;
with lib.custom;
let
  cfg = config.<namespace>.<module>;
in {
  options.<namespace>.<module> = with types; { ... };
  config = mkIf cfg.enable { ... };
}
```

Both `with lib;` and `with lib.custom;` together is the convention used by `system.*`, `hardware.*`, `services.*`, `suites.*`, and most home modules — match the surrounding files rather than fighting it.

Acceptable alternatives when scoping is needed:
- `inherit (lib) mkIf mkMerge mkDefault types;` for explicit imports.
- `lib.mkIf`, `lib.types.str` inline.

### Conditionals
- Use `lib.mkIf condition { ... }` instead of `if condition then { ... } else { }`
- Use `lib.optionals condition [ items ]` for conditional lists
- Use `lib.optionalString condition "string"` for conditional strings
- Use `lib.mkMerge [ {...} {...} ]` to merge multiple attrsets conditionally

### Let-in Blocks
- Keep `let in` blocks scoped as close to usage as possible
- Define `cfg` variable: `cfg = config.custom.{path}.{to}.{module};`
- Extract complex expressions into named variables
- Use `inherit` to bring values into scope cleanly

### Naming Conventions
- **Variables/Options**: camelCase (`enableFeature`, `userName`)
- **Files/Directories**: kebab-case (`neovim/`, `home-manager/`, `default.nix`)
- **Nix functions**: camelCase (`mkOption`, `buildInputs`)
- **Boolean options**: prefix with verb (`enable`, `enableFeature`, `useDefaultConfig`)

### Function Parameters
Multi-line function parameters should follow this format:

```nix
{
  config,
  lib,
  pkgs,
  ...
}: let
  # let bindings
in {
  # body
}
```

### Indentation and Formatting
- Use **2 spaces** for indentation (never tabs)
- Open braces on same line: `{ config, lib, pkgs }`
- Closing brace and colon on separate line for multi-line: `...` then `}:`
- Format with `nix fmt` before committing

### Organization Principles
1. **Single Responsibility**: Each module should handle one logical feature
2. **Grouping**: Related options grouped together within module
3. **Dependencies**: Declare module dependencies explicitly
4. **Defaults**: Use `mkDefault` for values that should be overridable
5. **Assertions**: Add assertions for required options or invalid combinations

### Imports
```nix
# Group related imports
{
  config,
  lib,
  pkgs,
  inputs,        # Optional: flake inputs
  osConfig ? {}, # Optional: for home-manager modules
  ...
}:
```

### Module Options Best Practices

1. **Always provide descriptions** for options:
```nix
enable = mkBoolOpt false "Whether to enable the HTTP tools suite";
```

2. **Use appropriate types**:
```nix
port = mkOpt types.port 8080 "Port number";
package = mkOpt types.package pkgs.neovim "The package to use";
extraConfig = mkOpt types.lines "" "Extra configuration";
```

3. **Provide sensible defaults**:
```nix
fontSize = mkOpt types.int 12 "Default font size";
```

4. **Use nested options for complex config**:
```nix
options.custom.apps.neovim = {
  enable = mkBoolOpt false "Enable Neovim";
  
  plugins = {
    enable = mkBoolOpt true "Enable plugin support";
    extraPlugins = mkOpt (types.listOf types.package) [] "Additional plugins";
  };
};
```

### Configuration Implementation Best Practices

1. **Guard with mkIf**:
```nix
config = mkIf cfg.enable {
  # configuration only applied when enabled
};
```

2. **Platform conditionals**:
```nix
let
  is-linux = pkgs.stdenv.isLinux;
  is-darwin = pkgs.stdenv.isDarwin;
in {
  config = mkIf cfg.enable {
    home.packages = lib.optionals is-linux [ pkgs.linux-specific ];
  };
}
```

3. **Merge multiple configs conditionally**:
```nix
config = mkMerge [
  (mkIf cfg.enable {
    # base config
  })
  (mkIf (cfg.enable && cfg.extraFeatures) {
    # extra config
  })
];
```

### Secrets Management

This configuration uses SOPS for secrets management:

1. **System secrets** (NixOS/Darwin):
```nix
custom.security.sops = {
  enable = true;
  sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
  defaultSopsFile = lib.snowfall.fs.get-file "secrets/{hostname}/default.yaml";
};
```

2. **Home Manager secrets**:
```nix
sops = {
  age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
  defaultSopsFile = lib.snowfall.fs.get-file "secrets/{hostname}@{user}/default.yaml";
};
```

3. **Never commit**:
   - Private keys
   - Unencrypted secrets
   - API tokens
   - Passwords

4. **Secret files location**: `secrets/{hostname}/default.yaml`

### Reduce Repetition

1. **Use suites for common groupings**:
```nix
suites.common.enable = true;  # Enables: nix, fonts, audio, networking, ssh, etc.
```

2. **Create helper functions** in `lib/`:
```nix
mkService = name: port: {
  services.${name} = {
    enable = true;
    inherit port;
  };
};
```

3. **Use `genAttrs` for similar configs**:
```nix
programs = lib.genAttrs ["git" "vim" "tmux"] (_: lib.enabled);
```

## Snowfall Lib Conventions

### File Discovery
Snowfall automatically discovers:
- Systems in `systems/{arch}/{hostname}/default.nix`
- Homes in `homes/{arch}/{user}@{hostname}/default.nix`
- Modules in `modules/{nixos,darwin,home,shared}/`
- Packages in `packages/{name}/default.nix`
- Overlays in `overlays/{name}/default.nix`

### Namespace
All custom options are under the `custom` namespace (defined in `flake.nix`):
```nix
snowfall.namespace = "custom";
```

Access via:
- `config.custom.*` in modules
- `pkgs.custom.*` for custom packages
- `lib.custom.*` for custom lib functions

### Helper Functions
Available through `lib.snowfall`:
- `lib.snowfall.fs.get-file "path"` - Get file path relative to flake root
- Use for secrets: `defaultSopsFile = lib.snowfall.fs.get-file "secrets/host/default.yaml";`

## Notable Flake Inputs

Defined in `flake.nix`:

| Input | Purpose |
|---|---|
| `nixpkgs` | `nixos-26.05` (stable channel) |
| `unstable` | `nixos-unstable`; exposed as `pkgs.unstable` via overlay in `flake.nix` |
| `determinate` | Determinate Nix; `determinate.nixosModules.default` is auto-imported into every NixOS system |
| `snowfall-lib` | Flake structure (`lib.mkFlake`, file discovery, namespace) |
| `home-manager` | `release-26.05` |
| `sops-nix` | Secrets; `nixosModules.sops` auto-imported into systems, `homeManagerModules.sops` into homes |
| `deploy-rs` | Remote deploys (driven by `lib.mkDeploy`) |
| `wallpapers-nix` | `sbulav/wallpapers-nix`; consumed by desktop wallpaper addons |
| `whisper-dictation` | Speech-to-text helper |

The `darwin` input tracks the matching `nix-darwin-26.05` release branch. Determinate and SOPS provide their current Darwin modules directly; Homebrew is managed through nix-darwin's built-in Homebrew module.

## System Configuration Pattern

Host configurations in `systems/{arch}/{hostname}/default.nix`:

```nix
{
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [./hardware-configuration.nix];

  # Enable suites (groups of related modules)
  suites.common.enable = true;
  suites.desktop.enable = true;
  
  # Enable specific modules
  custom.virtualisation.podman.enable = true;
  custom.security.sops.enable = true;

  # System-specific packages
  environment.systemPackages = with pkgs; [
    # host-specific packages
  ];

  # ======================== DO NOT CHANGE THIS ========================
  system.stateVersion = "23.11";  # Or whatever version the system was installed with
  # ======================== DO NOT CHANGE THIS ========================
}
```

## Home Manager Configuration Pattern

User configurations in `homes/{arch}/{user}@{hostname}/default.nix`:

```nix
{
  config,
  lib,
  pkgs,
  ...
}: {
  custom.user = {
    enable = true;
    name = "username";
    fullName = "Full Name";
    email = "email@example.com";
  };

  # Enable home modules
  custom.cli-apps.neovim.enable = true;
  custom.tools.git.enable = true;

  # Home Manager specific config
  home.packages = with pkgs; [
    # user-specific packages
  ];

  # ======================== DO NOT CHANGE THIS ========================
  home.stateVersion = "23.11";
  # ======================== DO NOT CHANGE THIS ========================
}
```

## Common Patterns & Examples

### Adding a New Module

1. Create file in appropriate location:
   - System module: `modules/nixos/{category}/{name}/default.nix`
   - Darwin module: `modules/darwin/{category}/{name}/default.nix`
   - Home module: `modules/home/{category}/{name}/default.nix`

2. Follow module structure template above

3. Module is automatically discovered by Snowfall Lib

4. Enable in system/home config: `custom.{category}.{name}.enable = true;`

### Creating a Suite

Suites group related modules (see `modules/nixos/suites/common/default.nix`):

```nix
{
  config,
  lib,
  ...
}:
with lib.custom; let
  inherit (lib) mkIf;
  cfg = config.suites.common;
in {
  options.suites.common = {
    enable = mkBoolOpt false "Enable the common suite";
  };

  config = mkIf cfg.enable {
    # Enable multiple related modules
    system.nix.enable = true;
    system.fonts.enable = true;
    hardware.audio.enable = true;
    custom.tools.http.enable = true;
  };
}
```

### Adding a Custom Package

1. Create `packages/{name}/default.nix`
2. Define package derivation
3. Access as `pkgs.custom.{name}` anywhere in configuration
4. Install: `environment.systemPackages = [ pkgs.custom.{name} ];`

### Creating an Overlay

1. Create `overlays/{name}/default.nix`
2. Return function: `final: prev: { ... }`
3. Automatically applied to all system configurations

## Testing Workflow

Before committing changes:

1. **Format code**: `nix fmt`
2. **Check flake**: `nix flake check`
3. **Build system**: `nix build .#nixosConfigurations.{hostname}.config.system.build.toplevel`
4. **Test locally**: `sys test` (preferred) or `sudo nixos-rebuild test --flake .#{hostname}` — ephemeral, no bootloader update. **ALWAYS ASK BEFORE SWITCHING.**
5. **Apply changes**: `sys rebuild` (preferred) or `sudo nixos-rebuild switch --flake .#{hostname}`. **ALWAYS ASK BEFORE SWITCHING.**

For remote systems:
1. Test build locally first
2. Deploy with: `nix run .#deploy.{hostname}` (deploy-rs)

### CI

- `.github/workflows/cachix.yaml` — builds the flake on every push and pushes results to cachix; an evaluation/build break will surface there.
- `.github/renovate.json` — Renovate keeps flake inputs current; expect periodic input bumps in PRs.

## Troubleshooting

### Common Issues

1. **Build fails with "option does not exist"**
   - Check option namespace: should be `custom.{category}.{module}.{option}`
   - Verify module is imported (Snowfall auto-imports from modules/)

2. **Infinite recursion**
   - Avoid circular dependencies between options
   - Check `cfg` references in `let` block

3. **Type errors**
   - Use correct type for options (types.str, types.int, types.bool, etc.)
   - Check `mkOpt` usage: `mkOpt types.{type} {default} "{description}"`

4. **Module not found**
   - Verify file structure matches Snowfall conventions
   - Check filename is `default.nix`

### Debug Commands

```bash
# Show all flake outputs
nix flake show

# Evaluate specific option
nix eval .#nixosConfigurations.{hostname}.config.{option.path}

# Build with full trace
nix build --show-trace .#nixosConfigurations.{hostname}.config.system.build.toplevel

# Check specific module
nix-instantiate --eval -E '(import ./modules/nixos/{path}/default.nix)'
```

## Important Reminders for AI Agents

1. **Always check existing patterns** before creating new code
2. **Use custom lib functions** (`lib.custom.mkOpt`, `lib.custom.mkBoolOpt`)
3. **Pick the right namespace** — `custom.*` for opinionated user features, `system.*` / `hardware.*` / `services.*` / `suites.*` for system-level wrappers. Match the surrounding directory.
4. **Follow the module template** structure consistently
5. **Run `nix fmt`** before considering changes complete
6. **Test builds** with `nix flake check` and `nix build`
7. **Never commit secrets** - use SOPS for sensitive data
8. **Respect `stateVersion`** - never change it after initial installation
9. **Use suites** for related module groups
10. **Darwin is live for `mba13`** — keep Darwin-specific modules isolated under `modules/darwin/` and portable user configuration under `modules/home/`.
11. **Match the surrounding `with lib;` style** — the repo uses `with lib; with lib.custom;` together; the absolute "avoid `with lib;`" rule was aspirational and not enforced.
12. **Reach for `sys` first** for daily rebuild/test/update/clean (see Workflow Wrapper section).


## References

- [Snowfall Lib Documentation](https://snowfall.org/guides/lib/)
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [Nix Darwin Manual](https://daiderd.com/nix-darwin/manual/index.html)
- [SOPS-Nix](https://github.com/Mic92/sops-nix)
