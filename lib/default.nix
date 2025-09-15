{
  pkgs ? {
    stdenv = {
      isDarwin = false;
      isLinux = true;
    };
  },
  config ? {},
  ...
}: let
  userHome = userName:
    if config ? home && config.home ? homeDirectory
    then config.home.homeDirectory
    else if
      config ? users
      && config.users ? users
      && builtins.hasAttr userName config.users.users
      && config.users.users.${userName} ? home
    then config.users.users.${userName}.home
    else if pkgs.stdenv.isDarwin
    then "/Users/${userName}"
    else if pkgs.stdenv.isLinux
    then "/home/${userName}"
    else "/home/${userName}";
in {
  override-meta = meta: package:
    package.overrideAttrs (_: {
      inherit meta;
    });

  # Smart secrets file resolution (simplified for now)
  getSecretsFile = hostName: userName: "secrets/${userName}/default.yaml";

  # Generate standard SOPS configuration
  mkSecretsConfig = {
    hostName,
    userName,
    platform ? "linux", # "linux" | "darwin"
    profile ? "home", # "home" | "system"
  }: let
    isHome = profile == "home";
    isDarwin = platform == "darwin";

    baseConfig = {
      defaultSopsFormat = "yaml";
    };

    platformConfig =
      if isDarwin
      then {
        age = {
          keyFile =
            if isHome
            then "/Users/${userName}/.config/sops/age/keys.txt"
            else "/var/lib/sops/age/keys.txt";
          sshKeyPaths =
            if isHome
            then ["/Users/${userName}/.ssh/id_ed25519"]
            else ["/etc/ssh/ssh_host_ed25519_key"];
        };
      }
      else {
        age = {
          generateKey = isHome;
          keyFile =
            if isHome
            then "/home/${userName}/.config/sops/age/keys.txt"
            else "/var/lib/sops/age/keys.txt";
          sshKeyPaths =
            if isHome
            then ["/home/${userName}/.ssh/id_ed25519"]
            else ["/etc/ssh/ssh_host_ed25519_key"];
        };
      };
  in
    baseConfig // platformConfig;

  # Standard secret definition with smart, cross-platform defaults
  # - On Linux: allow `uid`
  # - On Darwin: drop `uid` (nix-darwin has no such option) and rely on `owner`/`group`
  mkSecret = secretName: {
    sopsFile ? null,
    path ? null,
    owner ? null, # string user name if you want to set an owner on both platforms
    mode ? "0400",
    format ? "binary",
    restartUnits ? [],
    uid ? null, # numeric uid; ignored on darwin
    ...
  } @ args: let
    isDarwin = pkgs.stdenv.isDarwin;

    # Remove function-specific/private args; also drop uid unconditionally here
    # and re-add it conditionally (Linux only) below.
    stripped =
      builtins.removeAttrs args ["sopsFile" "path" "owner" "uid"];

    # Base fields that are always safe
    base =
      stripped
      // {
        inherit mode format restartUnits;
      }
      // (
        if sopsFile != null
        then {inherit sopsFile;}
        else {}
      )
      // (
        if path != null
        then {inherit path;}
        else {}
      )
      // (
        if owner != null
        then {inherit owner;}
        else {}
      );
  in
    # Re-attach uid only on Linux (NixOS); nix-darwin doesn’t support it.
    base
    // (
      if (!isDarwin && args ? uid && args.uid != null)
      then {uid = args.uid;}
      else {}
    );

  # Common secret templates (unchanged; any uid provided will be ignored on darwin)
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
      oidcClientSecret = serviceName: {
        uid = 999;
        restartUnits = ["container@${serviceName}.service"];
      };

      adminPassword = serviceName: {
        uid = 999;
        restartUnits = ["container@${serviceName}.service"];
      };

      appConfig = appName: {
        uid = 999;
        restartUnits = ["container@${appName}.service"];
      };

      envFileWithRestart = containerName: {
        uid = 999;
        restartUnits = ["container@${containerName}.service"];
      };

      cloudflareEnv = serviceName: {
        uid = 999;
        restartUnits = ["container@${serviceName}.service"];
      };
    };

    # Common service patterns
    services = {
      sharedTelegramBot = uid: {
        uid = uid; # 196 for grafana, 1000 for restic
      };

      unifiedEmailPassword = uid: {
        uid = uid;
      };

      backupPassword = backupName: {
        uid = 1000; # User-level backups
      };
    };

    # Special UID variants for services that need different UIDs
    special = {
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
      sshKey = keyName: hostName:
        if pkgs.stdenv.isDarwin
        then {
          mode = "0600";
        }
        else {
          uid = 0; # root
          mode = "0600";
        };

      hostSecret = secretName: hostName:
        if pkgs.stdenv.isDarwin
        then {
          mode = "0400";
        }
        else {
          uid = 0;
          mode = "0400";
        };
    };

    # Multi-secret patterns for complex services
    multiSecrets = {
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
