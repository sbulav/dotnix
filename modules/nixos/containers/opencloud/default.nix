{ lib, config, namespace, ... }:
let
  inherit (lib) mkIf types;
  inherit (lib.custom) mkBoolOpt mkOpt;

  cfg = config.${namespace}.containers.opencloud;

  opencloudPorts = [
    9100
    9110
    9115
    9130
    9140
    9142
    9144
    9146
    9150
    9154
    9157
    9160
    9164
    9166
    9178
    9185
    9186
    9190
    9191
    9199
    9200
    9215
    9216
    9220
    9233
    9242
    9280
    9282
    33177
    45023
    45363
    46833
    46871
  ];

  issuerUrl = "https://${cfg.oidc.issuerHost}";
  opencloudUrl = "https://${cfg.host}";
in {
  options.${namespace}.containers.opencloud = let
    oidcOpts = types.submodule {
      options = {
        clientId = mkOpt types.str "opencloud" "OIDC client identifier registered in Authelia.";
        issuerHost = mkOpt types.str "authelia.sbulav.ru" "Hostname of the Authelia issuer to trust.";
        roleClaim = mkOpt types.str "groups" "Claim containing the OpenCloud role mapping values.";
        adminGroup = mkOpt types.str "opencloudAdmin" "Claim value mapped to the OpenCloud administrator role.";
        spaceAdminGroup = mkOpt types.str "opencloudSpaceAdmin" "Claim value mapped to the OpenCloud space administrator role.";
        userGroup = mkOpt types.str "opencloudUser" "Claim value mapped to the OpenCloud user role.";
        guestGroup = mkOpt types.str "opencloudGuest" "Claim value mapped to the OpenCloud guest role.";
      };
    };
  in {
    enable = mkBoolOpt false "Enable the OpenCloud container.";
    secretFile = mkOpt types.str "secrets/serverz/default.yaml" "SOPS file that stores environment credentials for OpenCloud.";
    dataPath = mkOpt types.str "/tank/opencloud" "Host path that persists OpenCloud configuration and data.";
    host = mkOpt types.str "opencloud.sbulav.ru" "Public domain served by Traefik.";
    hostAddress = mkOpt types.str "172.16.64.10" "Host-side address for the container private network.";
    localAddress = mkOpt types.str "172.16.64.116" "Container-side address for the private network.";
    oidc = mkOpt oidcOpts {
      clientId = "opencloud";
      issuerHost = "authelia.sbulav.ru";
      roleClaim = "groups";
      adminGroup = "opencloudAdmin";
      spaceAdminGroup = "opencloudSpaceAdmin";
      userGroup = "opencloudUser";
      guestGroup = "opencloudGuest";
    } "OIDC integration parameters for Authelia.";
  };

  imports = [
    (import ../shared/shared-traefik-clientip-route.nix {
      app = "opencloud";
      host = cfg.host;
      url = "http://${cfg.localAddress}:9200";
      route_enabled = cfg.enable;
      middleware = [ "secure-headers" "allow-lan" ];
      clientips = "ClientIP(`172.16.64.0/24`) || ClientIP(`192.168.80.0/20`)";
    })
    (import ../shared/shared-traefik-route.nix {
      app = "opencloud";
      host = cfg.host;
      url = "http://${cfg.localAddress}:9200";
      route_enabled = cfg.enable;
      middleware = [ "secure-headers" "authelia" ];
    })
    (import ../shared/shared-adguard-dns-rewrite.nix {
      host = cfg.host;
      rewrite_enabled = cfg.enable;
    })
  ];

  config = mkIf cfg.enable (
    let
      envSecretPath = config.sops.secrets."opencloud-env".path;
    in {
      networking.nat = {
        enable = true;
        internalInterfaces = [ "ve-opencloud" ];
        externalInterface = "ens3";
      };

      custom.security.sops.secrets."opencloud-env" =
        lib.custom.secrets.containers.envFileWithRestart "opencloud"
        // {
          sopsFile = lib.snowfall.fs.get-file cfg.secretFile;
        };

      containers.opencloud = {
        ephemeral = true;
        autoStart = true;
        privateNetwork = true;
        hostAddress = cfg.hostAddress;
        localAddress = cfg.localAddress;

        bindMounts = {
          "${envSecretPath}" = {
            isReadOnly = true;
          };
          "/var/lib/opencloud" = {
            hostPath = "${cfg.dataPath}/data";
            isReadOnly = false;
          };
          "/etc/opencloud" = {
            hostPath = "${cfg.dataPath}/config";
            isReadOnly = false;
          };
        };

        config = { lib, ... }:
          let
            inherit (lib) mkForce;
          in {
            systemd.tmpfiles.rules = [
              "d /var/lib/opencloud 0750 opencloud opencloud -"
              "d /etc/opencloud 0750 opencloud opencloud -"
            ];

            networking = {
              hosts."${cfg.hostAddress}" = [ cfg.oidc.issuerHost cfg.host ];
              firewall = {
                enable = true;
                allowedTCPPorts = opencloudPorts;
              };
              useHostResolvConf = mkForce true;
            };

            services.resolved.enable = false;

            services.opencloud = {
              enable = true;
              address = cfg.localAddress;
              port = 9200;
              url = opencloudUrl;
              stateDir = "/var/lib/opencloud";
              environmentFile = envSecretPath;
              settings = {
                proxy = {
                  autoprovision_accounts = true;
                  user_oidc_claim = "preferred_username";
                  user_cs3_claim = "username";
                  auto_provision_claims = {
                    username = "preferred_username";
                    email = "email";
                    display_name = "name";
                    groups = cfg.oidc.roleClaim;
                  };
                  oidc = {
                    issuer = issuerUrl;
                    rewrite_well_known = true;
                  };
                  role_assignment = {
                    driver = "oidc";
                    oidc_role_mapper = {
                      role_claim = cfg.oidc.roleClaim;
                      role_mapping = [
                        {
                          role_name = "admin";
                          claim_value = cfg.oidc.adminGroup;
                        }
                        {
                          role_name = "spaceadmin";
                          claim_value = cfg.oidc.spaceAdminGroup;
                        }
                        {
                          role_name = "user";
                          claim_value = cfg.oidc.userGroup;
                        }
                        {
                          role_name = "guest";
                          claim_value = cfg.oidc.guestGroup;
                        }
                      ];
                    };
                  };
                };
                web.web.config = {
                  server = opencloudUrl;
                  oidc = {
                    authority = issuerUrl;
                    client_id = cfg.oidc.clientId;
                    response_type = "code";
                    scope = "openid profile email groups";
                    post_logout_redirect_uri = opencloudUrl;
                  };
                };
              };
            };

            system.stateVersion = "24.11";
          };
    }
  );
}
