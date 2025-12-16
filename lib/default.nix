{
  pkgs ? {
    stdenv = {
      isDarwin = false;
      isLinux = true;
    };
  },
  config ? { },
  ...
}:
let
  stdenv = pkgs.stdenv or { };
  systemFromStdenv =
    if stdenv ? hostPlatform && stdenv.hostPlatform ? system then stdenv.hostPlatform.system else null;
  systemFromPkgs = pkgs.system or null;
  systemFromConfig =
    if config ? nixpkgs && config.nixpkgs ? hostPlatform && config.nixpkgs.hostPlatform ? system then
      config.nixpkgs.hostPlatform.system
    else
      null;
  systemFallback = if builtins ? currentSystem then builtins.currentSystem else null;

  systemName =
    if systemFromConfig != null then
      systemFromConfig
    else if systemFromStdenv != null then
      systemFromStdenv
    else if systemFromPkgs != null then
      systemFromPkgs
    else if systemFallback != null then
      systemFallback
    else
      "unknown";

  detectedDarwin = (builtins.match ".*-darwin" systemName) != null;

  # OS detection derived from pkgs (fallback to system name if pkgs lacks metadata)
  isDarwin = (stdenv.isDarwin or false) || detectedDarwin;
  isLinux = (stdenv.isLinux or false) || (!isDarwin);

  # Detect whether we're in a Home Manager context
  hasHomeCfg = config ? home && config.home ? homeDirectory;

  # Resolve a user's home directory:
  # - Prefer Home Manager's configured home
  # - Fall back to system user config if present
  # - Otherwise use sensible OS defaults
  userHome =
    userName:
    if hasHomeCfg then
      config.home.homeDirectory
    else if
      config ? custom
      && config.custom ? user
      && config.custom.user ? home
      && config.custom.user.home != null
    then
      config.custom.user.home
    else if
      config ? users
      && config.users ? users
      && builtins.hasAttr userName config.users.users
      && config.users.users.${userName} ? home
    then
      config.users.users.${userName}.home
    else if isDarwin then
      "/Users/${userName}"
    else if isLinux then
      "/home/${userName}"
    else
      "/home/${userName}";
in
{
  # Simple meta override
  override-meta =
    meta: package:
    package.overrideAttrs (_: {
      inherit meta;
    });

  # Smart secrets file resolution (placeholder)
  getSecretsFile = hostName: userName: "secrets/${userName}/default.yaml";

  # Generate standard SOPS configuration with robust cross-platform defaults.
  # On Darwin: both HOME and SYSTEM use the user's Age key at $HOME/.config/sops/age/keys.txt
  # On Linux: HOME uses user key; SYSTEM uses /var/lib/sops/age/keys.txt
  mkSecretsConfig =
    {
      hostName,
      userName,
      # Callers may override, but defaults auto-detect.
      platform ? (if isDarwin then "darwin" else "linux"), # "linux" | "darwin"
      profile ? (if hasHomeCfg then "home" else "system"), # "home" | "system"
    }:
    let
      # Final flags (allow explicit override via args while keeping auto-detect sane)
      _isDarwin = (platform == "darwin") || isDarwin;
      isHome = hasHomeCfg || (profile == "home");

      # Compute a home directory for path defaults
      homeDir =
        if hasHomeCfg then
          config.home.homeDirectory
        else if _isDarwin then
          "/Users/${userName}"
        else
          "/home/${userName}";

      baseConfig = {
        defaultSopsFormat = "yaml";
      };

      platformConfig =
        if _isDarwin then
          {
            age = {
              # IMPORTANT: per request, Darwin uses the user's Age key for BOTH home & system
              keyFile = "${homeDir}/.config/sops/age/keys.txt";
              # Only generate a key automatically for Home Manager profiles
              generateKey = isHome;
              sshKeyPaths =
                if isHome then [ "${homeDir}/.ssh/id_ed25519" ] else [ "/etc/ssh/ssh_host_ed25519_key" ];
            };
          }
        else
          {
            age = {
              # On Linux it's safe/nice to auto-generate for Home Manager
              generateKey = isHome;
              keyFile = if isHome then "${homeDir}/.config/sops/age/keys.txt" else "/var/lib/sops/age/keys.txt";
              sshKeyPaths =
                if isHome then [ "${homeDir}/.ssh/id_ed25519" ] else [ "/etc/ssh/ssh_host_ed25519_key" ];
            };
          };
    in
    baseConfig // platformConfig;

  # Standard secret definition with smart, cross-platform defaults
  # - On Linux: allow `uid`
  # - On Darwin: drop `uid` (nix-darwin has no such option) and rely on `owner`/`group`
  mkSecret =
    secretName:
    {
      sopsFile ? null,
      path ? null,
      owner ? null, # string user name if you want to set an owner on both platforms
      mode ? "0400",
      format ? "binary",
      restartUnits ? [ ],
      uid ? null, # numeric uid; ignored on darwin
      ...
    }@args:
    let
      # Remove function-specific/private args; also drop uid unconditionally here
      # and re-add it conditionally (Linux only) below.
      stripped = builtins.removeAttrs args [
        "sopsFile"
        "path"
        "owner"
        "uid"
      ];

      # Base fields that are always safe
      base =
        stripped
        // {
          inherit mode format restartUnits;
        }
        // (if sopsFile != null then { inherit sopsFile; } else { })
        // (if path != null then { inherit path; } else { })
        // (if owner != null then { inherit owner; } else { });
    in
    # Re-attach uid only on Linux (NixOS); nix-darwin doesn’t support it.
    base // (if (!isDarwin && args ? uid && args.uid != null) then { uid = args.uid; } else { });

  # Common secret templates (uid will be ignored on darwin automatically)
  secrets = {
    # User environment credentials
    envCredentials =
      userArg:
      let
        argIsAttrs = builtins.isAttrs userArg;
        userName =
          if argIsAttrs then userArg.userName or (throw "envCredentials: userName is required") else userArg;
        homeDirOverride =
          if argIsAttrs && userArg ? homeDir && userArg.homeDir != null then userArg.homeDir else null;
        homeDir = if homeDirOverride != null then homeDirOverride else userHome userName;
      in
      {
        path = "${homeDir}/.ssh/sops-env-credentials";
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
      restartUnits = [ "${serviceName}.service" ];
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
        restartUnits = [ "container@${serviceName}.service" ];
      };

      adminPassword = serviceName: {
        uid = 999;
        restartUnits = [ "container@${serviceName}.service" ];
      };

      appConfig = appName: {
        uid = 999;
        restartUnits = [ "container@${appName}.service" ];
      };

      envFileWithRestart = containerName: {
        uid = 999;
        restartUnits = [ "container@${containerName}.service" ];
      };

      cloudflareEnv = serviceName: {
        uid = 999;
        restartUnits = [ "container@${serviceName}.service" ];
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
          restartUnits = [ "container@grafana.service" ];
        };

        adminPassword = {
          uid = 196;
          restartUnits = [ "container@grafana.service" ];
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
      sshKey =
        keyName: hostName:
        if isDarwin then
          {
            mode = "0600";
          }
        else
          {
            uid = 0; # root
            mode = "0600";
          };

      hostSecret =
        secretName: hostName:
        if isDarwin then
          {
            mode = "0400";
          }
        else
          {
            uid = 0;
            mode = "0400";
          };
    };

    # Multi-secret patterns for complex services
    multiSecrets = {
      authelia = serviceName: {
        "${serviceName}-storage-encryption-key" = {
          uid = 999;
          restartUnits = [ "container@${serviceName}.service" ];
        };
        "${serviceName}-jwt-secret" = {
          uid = 999;
          restartUnits = [ "container@${serviceName}.service" ];
        };
        "${serviceName}-session-secret" = {
          uid = 999;
          restartUnits = [ "container@${serviceName}.service" ];
        };
        "${serviceName}-jwt-rsa-key" = {
          uid = 999;
          restartUnits = [ "container@${serviceName}.service" ];
        };
      };
    };
  };

  # Telegram notification helpers
  telegram = rec {
    # Generate telegram notification script for service failures
    # Note: pkgs parameter must be provided by the calling module
    mkTelegramFailureScript =
      pkgs:
      {
        serviceName, # e.g., "restic-backups"
        friendlyName, # e.g., "Restic Backup"
        hostName,
        chatId, # Hardcoded: "681806836"
        priority ? "high", # "high" | "low"
        errorLogLines ? 10, # Number of error log lines to include
        getDetailsScript ? "", # Optional bash code for service-specific details
      }:
      let
        curl = "${pkgs.curl}/bin/curl";
        jq = "${pkgs.jq}/bin/jq";
      in
      ''
        #!/usr/bin/env bash
        set -euo pipefail

        # Message header
        message="🖥️ ${hostName} | ${friendlyName}\n🔥 FAILURE"

        # Service-specific details (if provided)
        ${
          if getDetailsScript != "" then
            ''
              echo "Extracting service details..."
              details=$(${getDetailsScript})
              if [ -n "$details" ]; then
                message="$message\n\n$details"
              fi
            ''
          else
            ""
        }

        # Error logs from journalctl
        ${
          if errorLogLines > 0 then
            ''
              echo "Fetching last ${toString errorLogLines} log lines..."
              error_logs=$(journalctl -u ${serviceName}.service -n ${toString errorLogLines} --no-pager 2>/dev/null | tail -${toString errorLogLines} || echo "No logs available")
              if [ -n "$error_logs" ] && [ "$error_logs" != "No logs available" ]; then
                message="$message\n\n📋 Last ${toString errorLogLines} log lines:\n$error_logs"
              fi
            ''
          else
            ""
        }

        # Send to Telegram
        disable_notification=${if priority == "low" then "true" else "false"}

        echo "Preparing telegram notification..."
        data=$(${jq} -n \
          --arg chat_id "${chatId}" \
          --arg text "$message" \
          --argjson disable_notification "$disable_notification" \
          '{chat_id: $chat_id, text: $text, disable_notification: $disable_notification}')

        echo "Sending telegram notification..."
        response=$(${curl} -s -X POST \
          -H 'Content-Type: application/json' \
          -d "$data" \
          "https://api.telegram.org/bot''${TELEGRAM_TOKEN}/sendMessage") || {
          echo "Failed to send telegram notification" >&2
          echo "Response: $response" >&2
          exit 1
        }

        echo "Notification sent successfully"
        echo "Response: $response"
      '';

    # Create systemd service for telegram notification
    # Note: pkgs parameter must be provided by the calling module
    mkTelegramFailureService =
      pkgs:
      {
        serviceName,
        friendlyName,
        hostName,
        chatId,
        secretPath,
        priority ? "high",
        errorLogLines ? 10,
        getDetailsScript ? "",
      }:
      {
        "${serviceName}-telegram-failure" = {
          description = "Telegram notification for ${friendlyName} failure";
          serviceConfig = {
            Type = "oneshot";
            EnvironmentFile = secretPath;
          };
          script = mkTelegramFailureScript pkgs {
            inherit
              serviceName
              friendlyName
              hostName
              chatId
              priority
              errorLogLines
              getDetailsScript
              ;
          };
        };
      };

    # Complete helper: creates notification service + manual test service
    # Note: pkgs parameter must be provided by the calling module
    mkTelegramNotifications =
      pkgs:
      {
        serviceName,
        friendlyName,
        hostName,
        chatId,
        secretPath,
        priority ? "high",
        errorLogLines ? 10,
        getDetailsScript ? "",
        enableTest ? true,
      }:
      let
        curl = "${pkgs.curl}/bin/curl";
        jq = "${pkgs.jq}/bin/jq";
      in
      {
        services =
          mkTelegramFailureService pkgs {
            inherit
              serviceName
              friendlyName
              hostName
              chatId
              secretPath
              priority
              errorLogLines
              getDetailsScript
              ;
          }
          // (
            if enableTest then
              {
                # Test service to manually trigger notification
                "${serviceName}-telegram-test" = {
                  description = "Test telegram notification for ${friendlyName}";
                  serviceConfig = {
                    Type = "oneshot";
                    EnvironmentFile = secretPath;
                  };
                  script = ''
                    #!/usr/bin/env bash
                    set -euo pipefail

                    echo "🧪 Sending TEST notification for ${friendlyName}..."

                    message="🖥️ ${hostName} | ${friendlyName}\n⚠️ TEST NOTIFICATION\n\nThis is a manual test. The service is working correctly."

                    disable_notification=${if priority == "low" then "true" else "false"}

                    data=$(${jq} -n \
                      --arg chat_id "${chatId}" \
                      --arg text "$message" \
                      --argjson disable_notification "$disable_notification" \
                      '{chat_id: $chat_id, text: $text, disable_notification: $disable_notification}')

                    echo "Sending test notification..."
                    response=$(${curl} -s -X POST \
                      -H 'Content-Type: application/json' \
                      -d "$data" \
                      "https://api.telegram.org/bot''${TELEGRAM_TOKEN}/sendMessage") || {
                      echo "Failed to send test notification" >&2
                      exit 1
                    }

                    echo "✅ Test notification sent successfully"
                    echo "Response: $response"
                  '';
                };
              }
            else
              { }
          );
      };
  };
}
