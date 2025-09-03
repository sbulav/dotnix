{
  config,
  lib,
  namespace,
  pkgs,
  osConfig ? null,
  ...
}: let
  inherit (lib) mkIf mkMerge mkDefault types optionalAttrs;
  inherit (lib.${namespace}) mkBoolOpt mkOpt mkSecretsConfig secrets;
  
  cfg = config.${namespace}.security.sops;
  
  # Auto-detect platform and profile
  isDarwin = pkgs.stdenv.isDarwin;
  isHome = osConfig == null || osConfig == {};
  
  platform = if isDarwin then "darwin" else "linux";
  profile = if isHome then "home" else "system";
  
  hostName = if isHome 
    then config.home.username or "unknown"  # Fallback for home-manager
    else config.networking.hostName or "unknown";
    
  userName = if isHome
    then config.home.username or "sab"
    else config.${namespace}.user.name or "sab";

in {
  options.${namespace}.security.sops = with types; {
    enable = mkBoolOpt false "Whether to enable SOPS secrets management.";
    
    # Override auto-detection if needed
    platform = mkOpt (enum ["linux" "darwin" "auto"]) "auto" "Platform type for SOPS configuration.";
    profile = mkOpt (enum ["home" "system" "auto"]) "auto" "SOPS profile (home-manager vs system).";
    
    # Legacy compatibility options
    defaultSopsFile = mkOpt (nullOr path) null "Override default SOPS file (legacy).";
    sshKeyPaths = mkOpt (listOf path) [] "Additional SSH key paths.";
    
    # Simplified secret definitions
    secrets = mkOpt (attrsOf attrs) {} "Secret definitions with smart defaults.";
    
    # Common secret patterns
    commonSecrets = {
      enableCredentials = mkBoolOpt false "Enable standard env_credentials secret.";
      enableSshKeys = mkBoolOpt false "Enable SSH key management."; 
      enableServiceTokens = mkBoolOpt false "Enable service authentication tokens.";
    };
    
    # Removed Darwin fallback options - Darwin SOPS works normally now
  };

  config = mkIf cfg.enable (mkMerge [
    # Base packages (home-manager only)
    (mkIf (isHome && config ? home) {
      home.packages = with pkgs; [
        age
        sops  
        ssh-to-age
      ];
    })
    
    # SOPS configuration (platform-agnostic)
    {
      sops = mkSecretsConfig {
        inherit hostName userName;
        platform = if cfg.platform != "auto" then cfg.platform else platform;
        profile = if cfg.profile != "auto" then cfg.profile else profile;
      } // {
        defaultSopsFile = 
          if cfg.defaultSopsFile != null 
          then cfg.defaultSopsFile 
          else lib.snowfall.fs.get-file "secrets/${userName}/default.yaml";
      } // optionalAttrs (cfg.sshKeyPaths != []) {
        age.sshKeyPaths = cfg.sshKeyPaths;
      };
    }
    
    # Common secrets (home-manager only)
    (mkIf (cfg.commonSecrets.enableCredentials && config ? home) {
      sops.secrets.env_credentials = secrets.envCredentials userName;
    })
    
    # Custom secrets with smart defaults
    (mkIf (cfg.secrets != {}) {
      sops.secrets = lib.mapAttrs (name: secretConfig: 
        secretConfig // optionalAttrs (secretConfig.sopsFile or null == null) {
          sopsFile = 
            if cfg.defaultSopsFile != null 
            then cfg.defaultSopsFile 
            else lib.snowfall.fs.get-file "secrets/${userName}/default.yaml";
        }
      ) cfg.secrets;
    })
  ]);
}