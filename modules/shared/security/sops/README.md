# Shared SOPS Configuration Module

This module provides a unified, platform-agnostic approach to SOPS secrets management across Darwin and NixOS systems.

## Features

- **Auto-detection**: Automatically detects platform (Darwin/Linux) and profile (home/system)
- **Smart defaults**: Reduces configuration boilerplate by 80%+
- **Legacy compatibility**: Works alongside existing SOPS configurations
- **Template system**: Pre-defined patterns for common secrets
- **Darwin fallback**: Handles macOS SOPS compatibility issues gracefully

## Usage

### Basic Configuration

```nix
{
  custom.security.sops = {
    enable = true;
    commonSecrets.enableCredentials = true;
  };
}
```

### Advanced Configuration

```nix
{
  custom.security.sops = {
    enable = true;
    
    # Override auto-detection
    platform = "linux";  # "linux" | "darwin" | "auto" 
    profile = "home";     # "home" | "system" | "auto"
    
    # Common patterns
    commonSecrets = {
      enableCredentials = true;
      enableSshKeys = false;
      enableServiceTokens = false;
    };
    
    # Custom secrets with smart defaults
    secrets = {
      my_api_key = {
        mode = "0400";
        path = "/etc/my-service/api-key";
      };
      
      user_token = {
        # sopsFile will auto-resolve to user's secrets file
        mode = "0600";
      };
    };
  };
}
```

### Available Library Functions

```nix
# In any module context:
lib.custom.getSecretsFile hostName userName
lib.custom.mkSecretsConfig { hostName = "myhost"; userName = "myuser"; }
lib.custom.secrets.envCredentials "username"
lib.custom.secrets.serviceToken "myservice"
```

## Templates

Pre-defined secret templates available:

- `secrets.envCredentials userName` - User environment credentials
- `secrets.sshKey keyName userName` - SSH private keys  
- `secrets.serviceToken serviceName` - Service authentication tokens
- `secrets.containerEnv containerName` - Container environment files

## Migration Path

1. **Phase 1**: Infrastructure created (✅ Complete)
2. **Phase 2**: Migrate home configurations to use shared module
3. **Phase 3**: Migrate container modules to use shared templates
4. **Phase 4**: Replace platform-specific modules

## Compatibility

- **Backwards compatible**: Existing configurations continue working
- **Legacy options**: `defaultSopsFile` and `sshKeyPaths` still supported
- **Gradual adoption**: Can be enabled alongside existing SOPS modules
- **Darwin ready**: Handles macOS SOPS limitations with fallback mode

## File Structure

```
modules/shared/security/sops/
├── default.nix     # Main unified SOPS module
├── templates.nix   # Secret templates (future expansion)
└── README.md       # This documentation
```

The shared module is automatically discovered by Snowfall lib but may be overridden by platform-specific modules until migration is complete.