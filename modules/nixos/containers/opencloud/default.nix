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
      middleware = [ "secure-headers" ];
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
      ephemeral = true;
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
            environmentFile = "/run/secrets/opencloud-env";

            environment = {
              OC_INSECURE = "true";
              OC_LOG_LEVEL = "info";

              OC_EXCLUDE_RUN_SERVICES = "idp";
              OC_OIDC_ISSUER = issuerUrl;

              PROXY_AUTOPROVISION_ACCOUNTS = "true";
              PROXY_USER_OIDC_CLAIM = "preferred_username";
              PROXY_USER_CS3_CLAIM = "username";
              PROXY_OIDC_REWRITE_WELLKNOWN = "true";
              PROXY_OIDC_ACCESS_TOKEN_VERIFY_METHOD = "none";
              PROXY_ROLE_ASSIGNMENT_DRIVER = "oidc";
              PROXY_CSP_CONFIG_FILE_LOCATION = "/etc/opencloud/csp.yaml";

              WEB_OIDC_CLIENT_ID = cfg.oidcClientId;
              WEB_OIDC_SCOPE = "openid profile email groups offline_access";
              WEB_OIDC_METADATA_URL = "${issuerUrl}/.well-known/openid-configuration";

              GRAPH_USERNAME_MATCH = "none";
              GRAPH_ASSIGN_DEFAULT_USER_ROLE = "false";
            };

            settings = {
              proxy = {
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
