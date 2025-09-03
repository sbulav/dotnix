{ lib, namespace, ... }: let
  inherit (lib.${namespace}) mkSecret;
in {
  # User-level secrets
  user = {
    envCredentials = userName: mkSecret "env_credentials" {
      path = if builtins.pathExists "/home"
             then "/home/${userName}/.ssh/sops-env-credentials"
             else "/Users/${userName}/.ssh/sops-env-credentials";
      mode = "0600";
    };
    
    sshPrivateKey = keyName: userName: mkSecret "${keyName}_ssh_key" {
      path = if builtins.pathExists "/home"
             then "/home/${userName}/.ssh/${keyName}"
             else "/Users/${userName}/.ssh/${keyName}";
      mode = "0600";
    };
    
    atuin = userName: mkSecret "atuin_key" {
      path = if builtins.pathExists "/home"
             then "/home/${userName}/.local/share/atuin/key"
             else "/Users/${userName}/.local/share/atuin/key"; 
      mode = "0600";
    };
  };
  
  # Container service secrets  
  containers = {
    envFile = containerName: mkSecret "${containerName}-env" {
      path = "/var/lib/containers/${containerName}/.env";
      mode = "0400";
      owner = "root";
      group = "root";
    };
    
    dbPassword = serviceName: mkSecret "${serviceName}-db-password" {
      mode = "0400";
      restartUnits = ["${serviceName}.service"];
    };
    
    oidcSecret = serviceName: mkSecret "${serviceName}-oidc-secret" {
      mode = "0400"; 
      restartUnits = ["${serviceName}.service"];
    };
    
    certificateKey = serviceName: mkSecret "${serviceName}-cert-key" {
      mode = "0400";
      restartUnits = ["${serviceName}.service"];
    };
  };
  
  # Common service patterns
  services = {
    telegramBotToken = mkSecret "telegram-bot-token" {
      mode = "0400";
    };
    
    emailPassword = serviceName: mkSecret "${serviceName}-email-password" {
      mode = "0400";
      restartUnits = ["${serviceName}.service"];
    };
    
    backupPassword = backupName: mkSecret "backups/${backupName}" {
      mode = "0400";
    };
  };
}