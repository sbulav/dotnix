{ pkgs ? { stdenv = { isDarwin = false; isLinux = true; }; },
  config ? {}, ... }: let
  userHome = userName:
    if config ? home && config.home ? homeDirectory then
      config.home.homeDirectory
    else if config ? users && config.users ? users &&
      builtins.hasAttr userName config.users.users &&
      config.users.users.${userName} ? home then
        config.users.users.${userName}.home
    else if pkgs.stdenv.isDarwin then
      "/Users/${userName}"
    else if pkgs.stdenv.isLinux then
      "/home/${userName}"
    else
      "/home/${userName}";
in {
  override-meta = meta: package:
    package.overrideAttrs (_: {
      inherit meta;
    });

  # Smart secrets file resolution (simplified for now)
  # This will be called from within modules where lib.snowfall.fs is available
  getSecretsFile = hostName: userName: "secrets/${userName}/default.yaml";

  # Generate standard SOPS configuration
  mkSecretsConfig = {
    hostName,
    userName,
    platform ? "linux", # "linux" | "darwin"
    profile ? "home",   # "home" | "system" 
  }: let
    isHome = profile == "home";
    isDarwin = platform == "darwin";
    
    baseConfig = {
      defaultSopsFormat = "yaml";
    };
    
    platformConfig = if isDarwin then {
      age = {
        keyFile = if isHome 
          then "/Users/${userName}/.config/sops/age/keys.txt"
          else "/var/lib/sops/age/keys.txt";
        sshKeyPaths = if isHome 
          then ["/Users/${userName}/.ssh/id_ed25519"]
          else ["/etc/ssh/ssh_host_ed25519_key"];
      };
    } else {
      age = {
        generateKey = isHome;
        keyFile = if isHome 
          then "/home/${userName}/.config/sops/age/keys.txt"
          else "/var/lib/sops/age/keys.txt";
        sshKeyPaths = if isHome
          then ["/home/${userName}/.ssh/id_ed25519"] 
          else ["/etc/ssh/ssh_host_ed25519_key"];
      };
    };
  in
    baseConfig // platformConfig;

  # Standard secret definition with smart defaults
  mkSecret = secretName: {
    sopsFile ? null,
    path ? null,
    owner ? null,
    mode ? "0400",
    format ? "binary",
    restartUnits ? [],
    ...
  } @ args: let
    # Remove function-specific args to get the clean secret config
    secretConfig = builtins.removeAttrs args ["sopsFile" "path" "owner"];
  in
    secretConfig // {
      inherit mode format restartUnits;
    } // (if sopsFile != null then { inherit sopsFile; } else {})
      // (if path != null then { inherit path; } else {})
      // (if owner != null then { inherit owner; } else {});

  # Common secret templates
  secrets = {
    # User environment credentials
    envCredentials = userName: {
      path = "${userHome userName}/.ssh/sops-env-credentials";
      mode = "0600";
    };
    
    # SSH key secrets
    sshKey = keyName: userName: {
      path = "${userHome userName}/.ssh/${keyName}";
      mode = "0600";
    };
    
    # Service tokens with restart
    serviceToken = serviceName: {
      mode = "0400";
      restartUnits = ["${serviceName}.service"];
    };
    
    # Container environment files  
    containerEnv = containerName: {
      path = "/var/lib/containers/${containerName}/.env";
      mode = "0400";
    };
    
    # Container service templates
    containers = {
      # OIDC/OAuth client secrets (jellyfin, grafana, immich)
      oidcClientSecret = serviceName: {
        uid = 999;
        restartUnits = ["container@${serviceName}.service"];
      };
      
      # Admin passwords (nextcloud, grafana)
      adminPassword = serviceName: {
        uid = 999;
        restartUnits = ["container@${serviceName}.service"];
      };
      
      # Application config files (immich_config)
      appConfig = appName: {
        uid = 999;
        restartUnits = ["container@${appName}.service"];
      };
      
      # Environment files with restart (homepage, traefik)
      envFileWithRestart = containerName: {
        uid = 999;
        restartUnits = ["container@${containerName}.service"];
      };
      
      # Cloudflare credentials environment (traefik pattern)
      cloudflareEnv = serviceName: {
        uid = 999;
        restartUnits = ["container@${serviceName}.service"];
      };
    };
    
    # Common service patterns
    services = {
      # Shared telegram bot token (grafana + restic)
      sharedTelegramBot = uid: {
        uid = uid;  # 196 for grafana, 1000 for restic
      };
      
      # Unified email password (consolidate grafana + msmtp)
      unifiedEmailPassword = uid: {
        uid = uid;
      };
      
      # Backup repository passwords
      backupPassword = backupName: {
        uid = 1000;  # User-level backups
      };
    };
    
    # Special UID variants for services that need different UIDs
    special = {
      # Grafana uses UID 196
      grafana = {
        oidcClientSecret = {
          uid = 196;
          restartUnits = ["container@grafana.service"];
        };
        
        adminPassword = {
          uid = 196;
          restartUnits = ["container@grafana.service"];
        };
        
        telegramBot = {
          uid = 196;
        };
        
        emailPassword = {
          uid = 196;
        };
      };
    };
    
    # System-level secrets
    system = {
      # SSH keys for system services
      sshKey = keyName: hostName: {
        uid = 0;  # root
        mode = "0600";
      };
      
      # Host-specific system secrets
      hostSecret = secretName: hostName: {
        uid = 0;
        mode = "0400";
      };
    };
    
    # Multi-secret patterns for complex services
    multiSecrets = {
      # Authelia pattern (4 individual secrets with same config)
      authelia = serviceName: {
        "${serviceName}-storage-encryption-key" = {
          uid = 999;
          restartUnits = ["container@${serviceName}.service"];
        };
        "${serviceName}-jwt-secret" = {
          uid = 999;
          restartUnits = ["container@${serviceName}.service"];
        };
        "${serviceName}-session-secret" = {
          uid = 999;  
          restartUnits = ["container@${serviceName}.service"];
        };
        "${serviceName}-jwt-rsa-key" = {
          uid = 999;
          restartUnits = ["container@${serviceName}.service"];
        };
      };
    };
  };
}
