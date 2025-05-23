{
  config,
  lib,
  namespace,
  pkgs,
  ...
}:
with lib;
with lib.custom; let
  cfg = config.${namespace}.containers.grafana;
in {
  options.${namespace}.containers.grafana = with types; {
    enable = mkBoolOpt false "Enable the grafana monitoring service ;";
    dataPath = mkOpt str "/tank/grafana" "Grafana data path on host machine";
    host = mkOpt str "grafana.sbulav.ru" "The host to serve grafana on";
    hostAddress = mkOpt str "172.16.64.10" "With private network, which address to use on Host";
    localAddress = mkOpt str "172.16.64.112" "With privateNetwork, which address to use in container";
    secret_file = mkOpt str "secrets/zanoza/default.yaml" "SOPS secret to get creds from";
  };

  imports = [
    (import ../shared/shared-traefik-clientip-route.nix
      {
        app = "grafana";
        host = cfg.host;
        url = "http://${cfg.localAddress}:3000";
        route_enabled = cfg.enable;
        middleware = ["secure-headers" "allow-lan"];
        clientips = "ClientIP(`172.16.64.0/24`) || ClientIP(`192.168.80.0/20`)";
      })
    (import ../shared/shared-traefik-route.nix
      {
        app = "grafana";
        host = cfg.host;
        url = "http://${cfg.localAddress}:3000";
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
      "grafana/oidc_client_secret" = {
        sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
        uid = 196;
      };
      "grafana/admin_password" = {
        sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
        uid = 196;
      };
      "telegram-notifications-bot-token" = {
        sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
        uid = 196;
      };
      "grafana/email-password" = {
        sopsFile = lib.snowfall.fs.get-file "${cfg.secret_file}";
        uid = 196;
      };
    };
    # Allow grafana to read all exporters via trusted interface
    networking.firewall.trustedInterfaces = ["ve-grafana"];
    containers.grafana = {
      ephemeral = true;
      autoStart = true;
      privateNetwork = true;
      # Need to add 172.16.64.0/18 on router
      hostAddress = "${cfg.hostAddress}";
      localAddress = "${cfg.localAddress}";

      # Mounting Cloudflare creds(email and dns api token) as file
      bindMounts = {
        "/var/lib/grafana/data" = {
          hostPath = "${cfg.dataPath}/data/";
          isReadOnly = false;
        };

        "${config.sops.secrets."grafana/oidc_client_secret".path}" = {
          isReadOnly = true;
        };
        "${config.sops.secrets."grafana/admin_password".path}" = {
          isReadOnly = true;
        };
        "${config.sops.secrets."telegram-notifications-bot-token".path}" = {
          isReadOnly = true;
        };
        "${config.sops.secrets."grafana/email-password".path}" = {
          isReadOnly = true;
        };
      };

      config = {...}: {
        services.grafana = {
          enable = true;
          settings = {
            server = {
              protocol = "http";
              http_addr = "${cfg.localAddress}";
              root_url = "https://${cfg.host}";
            };
            smtp = rec {
              enabled = true;
              user = "zppfan@gmail.com";
              from_name = "ZANOZA-notifications";
              from_address = user;
              host = "smtp.gmail.com:587";
              password = "$__file{${config.sops.secrets."grafana/email-password".path}}";
            };
            security = {
              admin_email = config.${namespace}.user.email;
              admin_password = "$__file{${
                config.sops.secrets."grafana/admin_password".path
              }}";
            };
            analytics.reporting_enabled = false;
            users.auto_assign_org = true;
            users.auto_assign_org_id = 1;
            auth = {
              signout_redirect_url = "https://authelia.sbulav.ru/application/o/grafana/end-session/";
              # oauth_auto_login = true;
            };
            "auth.generic_oauth" = {
              enabled = true;
              name = "Authelia";
              allow_sign_up = true;
              client_id = "grafana";
              client_secret = "$__file{${config.sops.secrets."grafana/oidc_client_secret".path}}";
              api_url = "https://authelia.sbulav.ru/api/oidc/userinfo";
              auth_url = "https://authelia.sbulav.ru/api/oidc/authorization";
              token_url = "https://authelia.sbulav.ru/api/oidc/token";
              empty_scopes = false;
              scopes = "openid profile email groups";
              groups_attribute_path = "groups";
              email_attribute_path = "email";
              login_attribute_path = "preferred_username";
              name_attribute_path = "name";
              role_attribute_path = "contains(groups[*], 'admin') && 'Admin' || contains(groups[*], 'editor') && 'Editor' || 'Viewer'";
            };
          };
          provision = {
            enable = true;
            alerting = {
              contactPoints.settings = {
                apiVersion = 1;
                contactPoints = [
                  {
                    name = "grafana-default-email";
                    receivers = [
                      {
                        uid = "basic-email";
                        type = "email";
                        settings.addresses = config.${namespace}.user.email;
                      }
                    ];
                  }

                  {
                    name = "Telegram";
                    receivers = [
                      {
                        type = "telegram";
                        uid = "telegram";
                        settings = {
                          chatid = "681806836";
                          bottoken = "\${TELEGRAM_TOKEN}";
                          uploadImage = false;
                          message = "{{ template \"alert_list\" . }}";
                          parse_mode = "HTML";
                        };
                      }
                    ];
                  }
                ];
              };
              rules.settings = let
                rules = builtins.fromJSON (builtins.readFile ./alerting/rules.json);
                # ruleIds = map (r: r.uid) rules;
              in {
                apiVersion = 1;
                groups = [
                  {
                    orgId = 1;
                    name = "zanoza";
                    folder = "ALERTS";
                    interval = "5m";
                    inherit rules;
                  }
                ];
                # deleteRules seems to happen after creating the above rules, effectively rolling back
                # any updates.
              };
              templates.path = ./alerting/templates.yaml;
            };

            datasources.settings = {
              datasources = let
                prometheus = {
                  name = "Prometheus";
                  type = "prometheus";
                  access = "proxy";
                  url = "http://${cfg.hostAddress}:9090";
                  isDefault = true;
                };
                loki =
                  if config.${namespace}.containers.loki.enable
                  then [
                    {
                      name = "Loki";
                      type = "loki";
                      access = "proxy";
                      url = "http://${cfg.hostAddress}:3030";
                    }
                  ]
                  else [];
              in
                [prometheus] ++ loki;
            };
            # TODO: add dashboard for UPS
            dashboards.settings.providers = let
              nodeExporterFull = {
                name = "Node Exporter Full";
                options.path = pkgs.fetchurl {
                  name = "node-exporter-full-37-grafana-dashboard.json";
                  url = "https://grafana.com/api/dashboards/1860/revisions/37/download";
                  hash = "sha256-1DE1aaanRHHeCOMWDGdOS1wBXxOF84UXAjJzT5Ek6mM=";
                };
                orgId = 1;
              };

              smartctlExporter = {
                name = "Smartctl Exporter";
                options.path = pkgs.fetchurl {
                  name = "smartctl-exporter-dashboard2.json";
                  url = "https://raw.githubusercontent.com/sbulav/grafana-dashboards/refs/heads/main/smartctl/smartctl.json";
                  hash = "sha256-B6cWUiGsM3dbx2BVUdnaqjYVQgTzd/y7DNm2Rq1Cvws=";
                };
                orgId = 1;
              };

              zfsStats = {
                name = "ZFS stats";
                options.path = pkgs.fetchurl {
                  name = "zfs-stats2.json";
                  url = "https://raw.githubusercontent.com/sbulav/grafana-dashboards/refs/heads/main/zfs/zfs-stats.json";
                  hash = "sha256-1+DFTJXC9w41dYVHiarCN3QqWX6WCE053Sj0BktE2Bg=";
                };
                orgId = 1;
              };
              logs =
                if config.${namespace}.containers.loki.enable
                then [
                  {
                    name = "Logs dashboard";
                    options.path = pkgs.fetchurl {
                      name = "logs-dashboard2.json";
                      url = "https://raw.githubusercontent.com/sbulav/grafana-dashboards/refs/heads/main/monitoring/Logs-promtail.json";
                      hash = "sha256-rBgTrpMWOphSOVXPHc7kayzuTy0PylPOzk50VSnRrRs=";
                    };
                    orgId = 1;
                  }
                ]
                else [];
              authelia =
                if config.${namespace}.containers.authelia.enable
                then [
                  {
                    name = "Authelia dashboard";
                    options.path = pkgs.fetchurl {
                      name = "authelia-dashboard.json";
                      url = "https://raw.githubusercontent.com/authelia/authelia/refs/heads/master/examples/grafana-dashboards/simple.json";
                      hash = "sha256-y+WbEev4ezdJyorjnnZi37CL1Pd9PxYAvl5N0hsFJnk=";
                    };
                    orgId = 1;
                  }
                ]
                else [];
              traefik =
                if config.${namespace}.containers.traefik.enable
                then [
                  {
                    name = "Traefik via Loki dashboard";
                    options.path = pkgs.fetchurl {
                      name = "traefik-via-loki-dashboard2.json";
                      url = "https://raw.githubusercontent.com/sbulav/grafana-dashboards/refs/heads/main/traefik/traefik-via-loki.json";
                      hash = "sha256-jKXBG3PGYHwJVAkN44U7BmQ+KsHWE4KVAGllb3kt7g4=";
                    };
                    orgId = 1;
                  }
                ]
                else [];
              nut =
                if config.${namespace}.containers.ups.enable
                then [
                  {
                    name = "UPS info via NUT prometheus exporter";
                    options.path = pkgs.fetchurl {
                      name = "prometheus-nut-exporter2.json";
                      url = "https://raw.githubusercontent.com/sbulav/grafana-dashboards/refs/heads/main/ups/prometheus-nut-exporter.json";
                      hash = "sha256-quC1L5wv2iCcX5aorSFSDdp1napV69+FcPW+aQyqBtc=";
                    };
                    orgId = 1;
                  }
                ]
                else [];
            in
              [nodeExporterFull smartctlExporter zfsStats] ++ logs ++ authelia ++ traefik ++ nut;
          };
        };

        systemd.services.grafana = {
          serviceConfig = {
            EnvironmentFile = [
              config.sops.secrets."telegram-notifications-bot-token".path
            ];
          };
        };
        networking = {
          firewall = {
            enable = true;
            allowedTCPPorts = [3000];
          };
          # Use systemd-resolved inside the container
          # Workaround for bug https://github.com/NixOS/nixpkgs/issues/162686
          useHostResolvConf = lib.mkForce true;
        };
        services.resolved.enable = false;
        system.stateVersion = "24.11";
      };
    };
  };
}
