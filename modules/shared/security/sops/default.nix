{
  config,
  lib,
  pkgs,
  osConfig ? null,
  ...
}: let
  inherit (lib) attrByPath hasAttrByPath mkIf mkMerge mkDefault types optionalAttrs;
  inherit (lib.custom) mkBoolOpt mkOpt mkSecretsConfig secrets;

  cfg = config.custom.security.sops;

  # Auto-detect platform and profile
  detectedPlatform =
    if pkgs.stdenv.isDarwin
    then "darwin"
    else "linux";

  hasHomeUser = hasAttrByPath ["home" "username"] config;
  hasHomeDirectory = hasAttrByPath ["home" "homeDirectory"] config;
  hasHomeConfig = hasHomeUser || hasHomeDirectory;

  profile =
    if cfg.profile != "auto"
    then cfg.profile
    else if hasHomeConfig
    then "home"
    else "system";

  platform =
    if cfg.platform != "auto"
    then cfg.platform
    else detectedPlatform;

  hostName =
    if profile == "home"
    then attrByPath ["home" "username"] "unknown" config # Fallback for home-manager
    else attrByPath ["networking" "hostName"] "unknown" config;

  userName =
    if profile == "home"
    then attrByPath ["home" "username"] "sab" config
    else attrByPath ["custom" "user" "name"] "sab" config;

  homeDirectory =
    if profile == "home"
    then attrByPath ["home" "homeDirectory"] null config
    else null;
in {
  options.custom.security.sops = with types; {
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
    (mkIf (profile == "home") {
      home.packages = with pkgs; [
        age
        sops
        ssh-to-age
      ];
    })

    (mkIf (profile == "home" && homeDirectory != null) {
      home.sessionVariables.SOPS_AGE_KEY_FILE =
        "${homeDirectory}/.config/sops/age/keys.txt";
    })

    # SOPS configuration (platform-agnostic)
    {
      sops =
        mkSecretsConfig {
          inherit hostName userName;
          inherit platform profile;
        }
        // {
          defaultSopsFile =
            if cfg.defaultSopsFile != null
            then cfg.defaultSopsFile
            else lib.snowfall.fs.get-file "secrets/${userName}/default.yaml";
        }
        // optionalAttrs (cfg.sshKeyPaths != [] && profile != "home") {
          age.sshKeyPaths = cfg.sshKeyPaths;
        };
    }

    # Common secrets (home-manager only)
    (mkIf (cfg.commonSecrets.enableCredentials && profile == "home") {
      sops.secrets.env_credentials = secrets.envCredentials userName;
    })

    # Custom secrets with smart defaults
    (mkIf (cfg.secrets != {}) {
      sops.secrets =
        lib.mapAttrs (
          name: secretConfig:
            secretConfig
            // optionalAttrs (secretConfig.sopsFile or null == null) {
              sopsFile =
                if cfg.defaultSopsFile != null
                then cfg.defaultSopsFile
                else lib.snowfall.fs.get-file "secrets/${userName}/default.yaml";
            }
        )
        cfg.secrets;
    })
  ]);
}
