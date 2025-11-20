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

## Build/Test Commands

### System Operations
- **Build NixOS system**: `nix build .#nixosConfigurations.{hostname}.config.system.build.toplevel`
  - Available hosts: `nz`, `zanoza`, `mz`, `beez`
- **Build Darwin system**: `nix build .#darwinConfigurations.mbp16.config.system.build.toplevel`
- **Rebuild NixOS locally**: `sudo nixos-rebuild switch --flake .#{hostname}`
- **Rebuild Darwin locally**: `darwin-rebuild switch --flake .#mbp16`
- **Deploy to remote**: `nix run .#deploy.{hostname}` (zanoza, nz, mz)

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
├── shells/                # Development shells
└── secrets/               # SOPS encrypted secrets
```

## Module Development Guidelines

### Module Structure

Every module should follow this pattern:

```nix
{
  options,
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom; let
  cfg = config.custom.{category}.{module-name};
in {
  options.custom.{category}.{module-name} = with types; {
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

### Option Namespacing

All custom options MUST be namespaced under `custom.{category}.{module}`:

**Categories:**
- `custom.tools.*` - CLI tools and utilities
- `custom.cli-apps.*` - Interactive CLI applications
- `custom.apps.*` - GUI applications
- `custom.virtualisation.*` - Virtualization tools
- `custom.security.*` - Security and secrets
- `custom.user.*` - User configuration
- `suites.*` - Grouped module suites (common, desktop, develop, games)

**Examples:**
```nix
custom.tools.http.enable = true;
custom.cli-apps.neovim.enable = true;
custom.security.sops.enable = true;
suites.common.enable = true;
```

## Code Style Guidelines

### Library Usage
- **AVOID**: `with lib;` at the top level
- **PREFER**: `with lib.custom; let ... in` pattern
- **OR**: Explicit imports: `inherit (lib) mkIf mkMerge mkDefault types;`
- **OR**: Inline prefixes: `lib.mkIf`, `lib.types.str`

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

3. **Use `mapAttrs` for similar configs**:
```nix
programs = lib.mapAttrs (_: lib.enabled) [
  "git"
  "vim"
  "tmux"
];
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
with lib;
with lib.custom; let
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
4. **Test locally**: `sudo nixos-rebuild test --flake .#{hostname}` (doesn't update bootloader)
5. **Apply changes**: `sudo nixos-rebuild switch --flake .#{hostname}`

For remote systems:
1. Test build locally first
2. Deploy with: `nix run .#deploy.{hostname}`

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
3. **Namespace all options** under `custom.{category}.{module}`
4. **Follow the module template** structure consistently
5. **Run `nix fmt`** before considering changes complete
6. **Test builds** with `nix flake check` and `nix build`
7. **Never commit secrets** - use SOPS for sensitive data
8. **Respect `stateVersion`** - never change it after initial installation
9. **Use suites** for related module groups
10. **Platform conditionals** when mixing Linux/Darwin configs

## References

- [Snowfall Lib Documentation](https://snowfall.org/guides/lib/)
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [Nix Darwin Manual](https://daiderd.com/nix-darwin/manual/index.html)
- [SOPS-Nix](https://github.com/Mic92/sops-nix)
