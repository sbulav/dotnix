# AGENTS.md - NixOS/Nix-Darwin Configuration

## Build/Test Commands
- **Format code**: `nix fmt` (if available, or use nixfmt manually)
- **Build specific system**: `nix build .#nixosConfigurations.nz.config.system.build.toplevel`
- **Build Darwin system**: `nix build .#darwinConfigurations.mbp16.config.system.build.toplevel`
- **Rebuild NixOS system**: `sudo nixos-rebuild switch --flake .#nz` (or zanoza, porez)
- **Check flake**: `nix flake check`
- **Update flake**: `nix flake update`
- **Deploy to remote**: `nix run .#deploy.zanoza` (or nz, porez)
- **Test in shell**: `nix shell nixpkgs#<package>`

## Code Style Guidelines
- **Library Usage**: Avoid `with lib;` - use `inherit (lib) ...` or inline `lib.` prefixes instead
- **Conditionals**: Prefer `lib.mkIf`, `lib.optionals`, `lib.optionalString` over `if then else`
- **Scope**: Keep `let in` blocks scoped as close to usage as possible
- **Naming**: Use camelCase for variables/options, kebab-case for files/directories
- **Options**: Define namespace-scoped options (`custom.<module>.<option>`)
- **Organization**: Group related items within modules, keep modules focused and single-purpose
- **Imports**: Group related imports together, use descriptive parameter names
- **Indentation**: Use 2-space indentation consistently
- **Function parameters**: Multi-line with `{` on first line, `...` and `}:` on separate lines
- **Reduce repetition**: Use Nix functions and abstractions to minimize duplicated code
- **Secrets**: Use sops-nix for secrets management following Snowfall lib conventions
