{
  config,
  lib,
  namespace,
  inputs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.${namespace}.containers.opencloud;
  issuerUrl = "https://${cfg.oidcIssuerHost}";
  opencloudUrl = "https://${cfg.host}";
in
{
  options.${namespace}.containers.opencloud = with types; {
    enable = mkBoolOpt false "Enable opencloud nixos-container;";
    secret_file = mkOpt str "secrets/zanoza/default.yaml" "SOPS secret to get creds from";
    dataPath = mkOpt str "/tank/opencloud" "OpenCloud data path on host machine";
    host = mkOpt str "opencloud.sbulav.ru" "The host to serve opencloud on";
    hostAddress = mkOpt str "172.16.64.10" "With private network, which address to use on Host";
    localAddress = mkOpt str "172.16.64.110" "With privateNetwork, which address to use in container";
    oidcIssuerHost = mkOpt str "authelia.sbulav.ru" "Hostname of the Authelia OIDC issuer";
    oidcClientId = mkOpt str "opencloud-web" "Web client ID registered in Authelia";
    adminGroup = mkOpt str "admins" "Authelia group that maps to the OpenCloud admin role";
    userGroup = mkOpt str "users" "Authelia group that maps to the OpenCloud user role";
  };

  imports = [
    (import ../shared/shared-traefik-route.nix {
      app = "opencloud";
      host = cfg.host;
      url = "http://${cfg.localAddress}:9200";
      route_enabled = cfg.enable;
      middleware = [ "secure-headers-opencloud" ];
    })
    (import ../shared/shared-adguard-dns-rewrite.nix {
      host = cfg.host;
      rewrite_enabled = cfg.enable;
    })
  ];

  config = mkIf cfg.enable {
    networking.nat = {
      enable = true;
      internalInterfaces = [ "ve-opencloud" ];
      externalInterface = "ens3";
    };

    custom.security.sops.secrets = {
      "opencloud-env" = lib.custom.secrets.containers.envFileWithRestart "opencloud" // {
        sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
      };
    };

    containers.opencloud = {
      # Non-ephemeral: the upstream NixOS module's `opencloud-init-config` oneshot
      # writes /etc/opencloud/opencloud.yaml with random internal-service secrets on
      # first run. With ephemeral=true that file (and the secrets) is regenerated on
      # every restart, invalidating IDM state and signed shares persisted in /var/lib.
      ephemeral = false;
      autoStart = true;

      privateNetwork = true;
      hostAddress = cfg.hostAddress;
      localAddress = cfg.localAddress;

      bindMounts = {
        "${config.sops.secrets."opencloud-env".path}" = {
          isReadOnly = true;
        };
        "/var/lib/opencloud" = {
          hostPath = "${cfg.dataPath}";
          isReadOnly = false;
        };
      };

      specialArgs = {
        inherit inputs;
      };

      config =
        {
          config,
          inputs,
          pkgs,
          lib,
          ...
        }:
        let
          unstable = inputs.unstable.legacyPackages.${pkgs.system};
        in
        {
          systemd.tmpfiles.rules = [
            "d /var/lib/opencloud 0750 opencloud opencloud -"
          ];

          services.opencloud = {
            enable = true;
            package = unstable.opencloud;
            webPackage = unstable.opencloud.web;
            idpWebPackage = unstable.opencloud.idp-web;

            address = cfg.localAddress;
            port = 9200;
            url = opencloudUrl;
            stateDir = "/var/lib/opencloud";
            # environmentFile is reserved for SECRETS only (OC_ADMIN_PASSWORD).
            # Non-secret config lives in `settings` (yaml) below so it stays declarative
            # and isn't silently shadowed by env entries written in sops.
            environmentFile = "/run/secrets/opencloud-env";

            # Truly global config that the upstream module reads from env across many
            # microservices. These have no clean yaml home, so they stay as env vars.
            environment = {
              OC_INSECURE = "true";
              OC_LOG_LEVEL = "info";
              OC_EXCLUDE_RUN_SERVICES = "idp";
              OC_OIDC_ISSUER = issuerUrl;
              # graph service: don't fall back to default role when OIDC mapping doesn't match
              GRAPH_USERNAME_MATCH = "none";
              GRAPH_ASSIGN_DEFAULT_USER_ROLE = "false";
            };

            settings = {
              proxy = {
                auto_provision_accounts = true;
                user_oidc_claim = "preferred_username";
                user_cs3_claim = "username";
                csp_config_file_location = "/etc/opencloud/csp.yaml";

                oidc = {
                  rewrite_well_known = true;
                  access_token_verify_method = "none";
                };

                role_assignment = {
                  driver = "oidc";
                  oidc_role_mapper = {
                    role_claim = "groups";
                    role_mapping = [
                      {
                        role_name = "admin";
                        claim_value = cfg.adminGroup;
                      }
                      {
                        role_name = "user";
                        claim_value = cfg.userGroup;
                      }
                    ];
                  };
                };
              };

              web.web.config.oidc = {
                client_id = cfg.oidcClientId;
                scope = "openid profile email groups offline_access";
                metadata_url = "${issuerUrl}/.well-known/openid-configuration";
              };

              csp = {
                directives = {
                  child-src = [ "'self'" ];
                  connect-src = [
                    "'self'"
                    "blob:"
                    "${issuerUrl}/"
                    "https://raw.githubusercontent.com/opencloud-eu/awesome-apps/"
                    "https://update.opencloud.eu/"
                  ];
                  default-src = [ "'none'" ];
                  font-src = [ "'self'" ];
                  frame-ancestors = [ "'self'" ];
                  frame-src = [
                    "'self'"
                    "blob:"
                    "${issuerUrl}/"
                    "https://docs.opencloud.eu"
                  ];
                  img-src = [
                    "'self'"
                    "data:"
                    "blob:"
                    "https://raw.githubusercontent.com/opencloud-eu/awesome-apps/"
                  ];
                  manifest-src = [ "'self'" ];
                  media-src = [ "'self'" ];
                  object-src = [
                    "'self'"
                    "blob:"
                  ];
                  script-src = [
                    "'self'"
                    "'unsafe-inline'"
                    "${issuerUrl}/"
                  ];
                  style-src = [
                    "'self'"
                    "'unsafe-inline'"
                  ];
                  worker-src = [
                    "'self'"
                    "blob:"
                  ];
                };
              };
            };
          };

          networking = {
            firewall = {
              enable = true;
              allowedTCPPorts = [ 9200 ];
            };
            useHostResolvConf = lib.mkForce false;
          };

          services.resolved = {
            enable = true;
            extraConfig = ''
              DNS=172.16.64.104
            '';
          };

          system.stateVersion = "25.11";
        };
    };
  };
}
