{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.custom; let
  cfg = config.${namespace}.containers.authelia;
in {
  options.${namespace}.containers.authelia = with types; {
    enable = mkBoolOpt false "Enable authelia nixos-container;";
    secret_file = mkOpt str "secrets/serverz/default.yaml" "SOPS secret to get creds from";
    dataPath = mkOpt str "/tank/authelia" "Authelia data path on host machine";
    host = mkOpt str "authelia.sbulav.ru" "The host to serve authentik on";
    domain = mkOpt str "sbulav.ru" "The domain session cookie to protect";
    hostAddress = mkOpt str "172.16.64.10" "With private network, which address to use on Host";
    localAddress = mkOpt str "172.16.64.103" "With privateNetwork, which address to use in container";
  };

  imports = [
    (import ../shared/shared-traefik-route.nix
      {
        app = "authelia";
        host = cfg.host;
        url = "http://${cfg.localAddress}:9091";
        middleware = "secure-headers";
        route_enabled = cfg.enable;
      })
    (import ../shared/shared-adguard-dns-rewrite.nix
      {
        host = cfg.host;
        rewrite_enabled = cfg.enable;
      })
  ];

  config = mkIf cfg.enable {
    sops.secrets = {
      authelia-storage-encryption-key = {
        sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
        uid = 999;
        restartUnits = ["container@authelia.service"];
      };
      authelia-jwt-secret = {
        sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
        uid = 999;
        restartUnits = ["container@authelia.service"];
      };
      authelia-session-secret = {
        sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
        uid = 999;
        restartUnits = ["container@authelia.service"];
      };
      "authelia-jwt-rsa-key" = {
        # format = "binary";
        sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
        uid = 999;
        restartUnits = ["container@authelia.service"];
      };
    };
    containers.authelia = {
      ephemeral = true;
      autoStart = true;

      privateNetwork = true;
      # Need to add 172.16.64.0/18 on router
      hostAddress = cfg.hostAddress;
      localAddress = cfg.localAddress;

      # Mounting Cloudflare creds(email and dns api token) as file
      bindMounts = {
        # "${config.sops.secrets.authelia-env.path}" = {
        #   isReadOnly = true;
        # };
        "${config.sops.secrets.authelia-storage-encryption-key.path}" = {
          isReadOnly = true;
        };
        "${config.sops.secrets.authelia-session-secret.path}" = {
          isReadOnly = true;
        };
        "${config.sops.secrets.authelia-jwt-secret.path}" = {
          isReadOnly = true;
        };
        "${config.sops.secrets.authelia-jwt-rsa-key.path}" = {
          isReadOnly = true;
        };

        "/var/lib/authelia-main/users/" = {
          hostPath = "${cfg.dataPath}/users/";
          isReadOnly = false;
        };
        "/var/lib/authelia-main/logs/" = {
          hostPath = "${cfg.dataPath}/logs/";
          isReadOnly = false;
        };
        "/var/lib/authelia-main/storage/" = {
          hostPath = "${cfg.dataPath}/storage/";
          isReadOnly = false;
        };
      };
      config = {...}: {
        time.timeZone = "Europe/Moscow";
        services.authelia.instances = {
          main = {
            enable = true;
            secrets = {
              storageEncryptionKeyFile = config.sops.secrets.authelia-storage-encryption-key.path;
              jwtSecretFile = config.sops.secrets.authelia-jwt-secret.path;
              sessionSecretFile = config.sops.secrets.authelia-session-secret.path;
              oidcIssuerPrivateKeyFile = config.sops.secrets.authelia-jwt-rsa-key.path;
            };

            settings = {
              log = {
                level = "info";
                file_path = "/var/lib/authelia-main/logs/authelia.log";
              };
              telemetry = {
                metrics = {
                  address = "tcp://${cfg.localAddress}:9959";
                  enabled = true;
                };
              };
              authentication_backend = {
                file.path = "/var/lib/authelia-main/users/users_database.yml";
                password_reset.disable = true;
              };

              storage.local.path = "/var/lib/authelia-main/storage/db.sqlite3";

              server = {
                disable_healthcheck = true;
                # Fix forward-auth for Jellyfin
                # See https://github.com/authelia/authelia/discussions/7472
                endpoints = {
                  authz = {
                    forward-auth = {
                      implementation = "ForwardAuth";
                    };
                  };
                };
              };
              regulation = {
                ban_time = 300;
                find_time = 120;
                max_retries = 3;
              };
              session = {
                name = "authelia_session";
                cookies = [
                  {
                    domain = cfg.domain;
                    authelia_url = "https://${cfg.host}";
                    default_redirection_url = "https://home.${cfg.domain}";
                    expiration = "48h";
                    inactivity = "24h";
                    remember_me = "1M";
                  }
                ];
              };
              default_2fa_method = "totp";
              # TODO: change notifier to smtp/2fa
              #used to send 2FA registration emails etc
              notifier = {
                disable_startup_check = false;
                filesystem = {
                  filename = "/var/lib/authelia-main/logs/notification.txt";
                };
              };
              access_control = {
                # default_policy = "deny";
                # default_policy = "one_factor";
                default_policy = "two_factor";
                rules = [
                  {
                    domain = "*.${cfg.domain}";
                    # policy = "one_factor";
                    policy = "two_factor";
                  }
                ];
              };

              identity_providers = {
                oidc = {
                  claims_policies = {
                    # https://github.com/pulsejet/nextcloud-oidc-login/issues/311
                    # https://www.authelia.com/integration/openid-connect/openid-connect-1.0-claims/#restore-functionality-prior-to-claims-parameter
                    nextcloud_policy.id_token = ["groups" "email" "email_verified" "alt_emails" "preferred_username" "name"];
                  };
                  clients = [
                    {
                      authorization_policy = "one_factor";
                      client_id = "jellyfin";
                      client_name = "Jellyfin";
                      client_secret = "$pbkdf2-sha512$310000$zsC4o9RfhpGEdyk6zlKtvw$ERgl4RYHk2IfILuFRfsOCcK.R1MYiyvUrU2XBgmYLSH5.DALMqw.5ZdRdIKAKAJakYHt/HkkB/lVf96uw6kGNg";
                      consent_mode = "implicit";
                      pkce_challenge_method = "S256";
                      public = "false";
                      redirect_uris = ["https://jellyfin.${cfg.domain}/sso/OID/redirect/authelia"];
                      require_pkce = true;
                      token_endpoint_auth_method = "client_secret_post";
                    }
                    {
                      authorization_policy = "one_factor";
                      client_id = "nextcloud";
                      client_name = "Nextcloud";
                      claims_policy = "nextcloud_policy";
                      client_secret = "$pbkdf2-sha512$310000$UO0xTTiZTXcj6cUL1R7P/A$4SQ.Zzv//x02/sZ5WM8EBPYd/Tps07K8.Zq19sjVVV6vIMCb.e5giDgHeZokgD3lBv4MOVlxttCjRU0dhFO15w";
                      consent_mode = "implicit";
                      pkce_challenge_method = "S256";
                      public = "false";
                      redirect_uris = ["https://nextcloud.${cfg.domain}/apps/oidc_login/oidc"];
                      require_pkce = true;
                      token_endpoint_auth_method = "client_secret_basic";
                      userinfo_signed_response_alg = "none";
                    }
                    {
                      authorization_policy = "one_factor";
                      client_id = "immich";
                      client_name = "Immich";
                      client_secret = "$pbkdf2-sha512$310000$JvS0PwAz3BIfHWAirUKiGg$eBr7wTY3GO2mQXp/U54Tmd4q.sv7qJdpiQzZgVD1V7YPk4VGGTBwhVhpKIF4S.0vu2pGw2KiI2yP37aelGKPaA";
                      consent_mode = "implicit";
                      public = "false";
                      redirect_uris = [
                        "https://immich.${cfg.domain}/apps/oidc_login/oidc"
                        "https://immich.${cfg.domain}/auth/login"
                        "https://immich.${cfg.domain}/user-settings"
                        "app.immich:///oauth-callback"
                      ];
                      token_endpoint_auth_method = "client_secret_basic";
                      userinfo_signed_response_alg = "none";
                    }
                    {
                      authorization_policy = "one_factor";
                      client_id = "grafana";
                      client_name = "grafana";
                      client_secret = "$pbkdf2-sha512$310000$4jNs4mRSxsVHn0Fz6n5CLw$McFHhCkX6ZPPNaNx0QdWHg67v7XQAwGKwtIWAAl2ODkUJ0fsaPUMNigVE9YAUd1zHHpODVjx9jQHIjbUXqBhGw";
                      consent_mode = "implicit";
                      public = "false";
                      redirect_uris = ["https://grafana.${cfg.domain}/login/generic_oauth"];
                      token_endpoint_auth_method = "client_secret_basic";
                      userinfo_signed_response_alg = "none";
                    }
                  ];
                };
              };
            };
          };
        };
        networking = {
          firewall = {
            enable = true;
            allowedTCPPorts = [9091 9959];
          };
          # Use systemd-resolved inside the container
          # Workaround for bug https://github.com/NixOS/nixpkgs/issues/162686
          useHostResolvConf = lib.mkForce false;
        };
        services.resolved.enable = true;
        system.stateVersion = "24.11";
      };
    };
  };
}
