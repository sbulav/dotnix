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
  systemFromPkgs = pkgs.stdenv.hostPlatform.system or null;
  systemFromConfig =
    if config ? nixpkgs && config.nixpkgs ? hostPlatform && config.nixpkgs.hostPlatform ? system then
      config.nixpkgs.hostPlatform.system
    else
      null;
  systemFallback = builtins.currentSystem or null;

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
  getSecretsFile = _hostName: userName: "secrets/${userName}/default.yaml";

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
    _secretName:
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
    base // (if (!isDarwin && args ? uid && args.uid != null) then { inherit (args) uid; } else { });

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
        inherit uid; # 196 for grafana, 1000 for restic
      };

      unifiedEmailPassword = uid: {
        inherit uid;
      };

      backupPassword = _backupName: {
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

        secretKey = {
          uid = 196;
          restartUnits = [ "container@grafana.service" ];
        };
      };
    };

    # System-level secrets
    system = {
      sshKey =
        _keyName: _hostName:
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
        _secretName: _hostName:
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
        # Same Gmail account as the Grafana alerts and msmtp.
        "${serviceName}-smtp-password" = {
          uid = 999;
          key = "shared/email-password";
          restartUnits = [ "container@${serviceName}.service" ];
        };
      };
    };
  };

  # The one notification delivery path for every alerting job (restic, the
  # monitors, the cache builder, sing-box): Telegram first (optionally through
  # a SOCKS/HTTP proxy, always with bounded timeouts), msmtp email as the
  # fallback.
  notifications = {
    # mkDeliverScript pkgs { ... } -> derivation with bin/notify-deliver
    #   notify-deliver <message-file> <subject> [high|low]
    #
    # Delivery order: Telegram (optional SOCKS proxy, prefer socks5h:// so DNS
    # is resolved remotely) and then email through msmtp when Telegram failed or
    # is unavailable. Exit 0 as soon as one channel accepted the message, exit 1
    # when every enabled channel failed; in that case the whole message is also
    # written to stderr so it survives in the journal of the calling unit.
    #
    # Contract for the calling systemd unit:
    #   - TELEGRAM_TOKEN comes from `EnvironmentFile = "-<sops path>"` (leading
    #     dash: a missing token file must not prevent the email fallback);
    #     without the variable Telegram is treated as failed.
    #   - FORCE_EMAIL_ONLY=true skips Telegram (fallback tests). With email
    #     disabled this always exits 1.
    #   - order the unit After=/Wants=network-online.target and give it a
    #     TimeoutStartSec; curl and msmtp are bounded, but the unit should not
    #     rely on that alone.
    mkDeliverScript =
      pkgs:
      {
        hostName,
        telegram ? { },
        email ? { },
      }:
      let
        tg = {
          enable = true;
          chatId = "";
          proxyUrl = "";
          connectTimeoutSeconds = 10;
          maxTimeSeconds = 30;
        }
        // telegram;
        mail = {
          enable = true;
          recipient = "";
          fromName = "${hostName} notifications";
          # Matches the shared custom.containers.msmtp module (account `gmail`).
          fromAddress = "zppfan@gmail.com";
          account = "gmail";
        }
        // email;
        # Telegram sendMessage rejects texts longer than 4096 characters.
        telegramTextLimit = 3900;
      in
      assert pkgs.lib.assertMsg (
        tg.enable || mail.enable
      ) "mkDeliverScript: enable Telegram, email or both";
      assert pkgs.lib.assertMsg (
        !tg.enable || tg.chatId != ""
      ) "mkDeliverScript: telegram.chatId is required when Telegram is enabled";
      assert pkgs.lib.assertMsg (
        !mail.enable || mail.recipient != ""
      ) "mkDeliverScript: email.recipient is required when email is enabled";
      assert pkgs.lib.assertMsg (
        tg.connectTimeoutSeconds > 0 && tg.maxTimeSeconds > 0
      ) "mkDeliverScript: curl timeouts must be positive (0 means unlimited)";
      pkgs.writeShellApplication {
        name = "notify-deliver";
        runtimeInputs =
          with pkgs;
          [
            coreutils
            curl
            jq
          ]
          ++ pkgs.lib.optional mail.enable msmtp;
        text = ''
          if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
            echo "usage: notify-deliver <message-file> <subject> [high|low]" >&2
            exit 2
          fi
          message_file="$1"
          subject="$2"
          priority="''${3:-high}"
          case "$priority" in
            high | low) ;;
            *)
              echo "notify-deliver: priority must be high or low, got '$priority'" >&2
              exit 2
              ;;
          esac
          # Header injection guard: a subject is a single line.
          subject=''${subject//$'\r'/}
          subject=''${subject//$'\n'/ }

          if [ ! -r "$message_file" ]; then
            echo "notify-deliver: message file $message_file is not readable" >&2
            exit 1
          fi

          work=$(mktemp -d)
          # shellcheck disable=SC2329
          cleanup() { rm -rf "$work"; }
          trap cleanup EXIT
          trap 'exit 143' TERM INT

          ${pkgs.lib.optionalString tg.enable ''
            telegram_attempted=false
            if [ "''${FORCE_EMAIL_ONLY:-false}" != true ]; then
              if [ -n "''${TELEGRAM_TOKEN:-}" ]; then
                telegram_attempted=true
                disable_notification=false
                if [ "$priority" = low ]; then
                  disable_notification=true
                fi
                # The token stays out of argv: curl reads URL and proxy from a
                # 0600 config file; the payload is streamed from a file so a
                # long journal tail cannot overflow the argument limit.
                if ! (
                  umask 077
                  {
                    printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$TELEGRAM_TOKEN"
                    ${pkgs.lib.optionalString (tg.proxyUrl != "") ''
                      printf 'proxy = "%s"\n' ${pkgs.lib.escapeShellArg tg.proxyUrl}
                    ''}
                  } >"$work/curl.cfg"
                ); then
                  echo "notify-deliver: could not write the curl config" >&2
                elif jq -n \
                  --arg chat_id ${pkgs.lib.escapeShellArg tg.chatId} \
                  --rawfile text "$message_file" \
                  --argjson disable_notification "$disable_notification" \
                  --argjson limit ${toString telegramTextLimit} \
                  '{chat_id: $chat_id,
                    text: ($text | if length > $limit then .[0:$limit] + "\n… [truncated]" else . end),
                    disable_notification: $disable_notification}' \
                  >"$work/payload.json"; then
                  if curl --fail-with-body --silent --show-error \
                    --connect-timeout ${toString tg.connectTimeoutSeconds} \
                    --max-time ${toString tg.maxTimeSeconds} \
                    -K "$work/curl.cfg" \
                    -H 'Content-Type: application/json' \
                    --data-binary @"$work/payload.json" \
                    -o "$work/response.json" \
                    && jq -e '.ok == true' "$work/response.json" >/dev/null; then
                    echo "notify-deliver: delivered via Telegram"
                    exit 0
                  fi
                else
                  echo "notify-deliver: could not build the Telegram payload (invalid UTF-8?)" >&2
                fi
                echo "notify-deliver: Telegram delivery failed${pkgs.lib.optionalString mail.enable "; using email fallback"}" >&2
              else
                echo "notify-deliver: TELEGRAM_TOKEN is unavailable${pkgs.lib.optionalString mail.enable "; using email fallback"}" >&2
              fi
            fi
          ''}

          ${
            if mail.enable then
              ''
                if {
                  printf 'From: %s <%s>\n' ${pkgs.lib.escapeShellArg mail.fromName} ${pkgs.lib.escapeShellArg mail.fromAddress}
                  printf 'To: %s\n' ${pkgs.lib.escapeShellArg mail.recipient}
                  printf 'Subject: %s\n' "$subject"
                  printf 'Content-Type: text/plain; charset=UTF-8\n\n'
                  cat "$message_file"
                } | timeout 60 msmtp -a ${pkgs.lib.escapeShellArg mail.account} ${pkgs.lib.escapeShellArg mail.recipient}; then
                  echo "notify-deliver: delivered via email"
                  exit 0
                fi
                echo "notify-deliver: email delivery failed" >&2
              ''
            else
              ''
                echo "notify-deliver: no notification channel delivered the message" >&2
              ''
          }
          ${pkgs.lib.optionalString tg.enable ''
            if [ "$telegram_attempted" = false ] && [ "''${FORCE_EMAIL_ONLY:-false}" = true ]; then
              echo "notify-deliver: Telegram was skipped (FORCE_EMAIL_ONLY)" >&2
            fi
          ''}
          echo "notify-deliver: undelivered message follows (subject: $subject)" >&2
          cat "$message_file" >&2
          exit 1
        '';
      };
  };
}
