_: {
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
      path = if builtins.pathExists "/home"
             then "/home/${userName}/.ssh/sops-env-credentials"
             else "/Users/${userName}/.ssh/sops-env-credentials";
      mode = "0600";
    };
    
    # SSH key secrets
    sshKey = keyName: userName: {
      path = if builtins.pathExists "/home"
             then "/home/${userName}/.ssh/${keyName}"
             else "/Users/${userName}/.ssh/${keyName}";
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
  };
}
