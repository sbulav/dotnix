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
  };

  imports = [
    (import ../shared/shared-traefik-route.nix
      {
        app = "grafana";
        host = "${cfg.host}";
        url = "http://${cfg.localAddress}:3000";
        route_enabled = cfg.enable;
      })
    (import ../shared/shared-adguard-dns-rewrite.nix
      {
        host = "${cfg.host}";
        rewrite_enabled = cfg.enable;
      })
  ];

  config = mkIf cfg.enable {
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
      };

      config = {...}: {
        # TODO: set up initial admin password via SOPS ()
        # TODO: configure OIDC authentication via ENVIRONMENT variables https://www.authelia.com/integration/openid-connect/grafana/
        services.grafana = {
          enable = true;
          # settings.server.http_addr = "${cfg.localAddress}";
          settings = {
            server.protocol = "http";
            server.http_addr = "${cfg.localAddress}";
            analytics.reporting_enabled = false;
          };
          provision = {
            enable = true;
            datasources.settings = {
              datasources = [
                {
                  name = "Prometheus";
                  type = "prometheus";
                  access = "proxy";
                  url = "http://${cfg.hostAddress}:9090";
                  isDefault = true;
                }
              ];
            };
            # TODO: add dashboard for ZFS
            # TODO: add dashboard for UPS
            dashboards.settings.providers = [
              {
                name = "Node Exporter Full";
                options.path = pkgs.fetchurl {
                  name = "node-exporter-full-37-grafana-dashboard.json";
                  url = "https://grafana.com/api/dashboards/1860/revisions/37/download";
                  hash = "sha256-1DE1aaanRHHeCOMWDGdOS1wBXxOF84UXAjJzT5Ek6mM=";
                };
                orgId = 1;
              }
              {
                name = "Smartctl Exporter";
                options.path = pkgs.fetchurl {
                  name = "smartctl-exporter-dashboard.json";
                  url = "https://raw.githubusercontent.com/blesswinsamuel/grafana-dashboards/refs/heads/main/dashboards/dist/dashboards/smartctl.json";
                  hash = "sha256-LtFe8ssPt1efIqTl94NLKVmuSuZWT8Hlu6ADNmb63h0=";
                };
                orgId = 1;
              }
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
          useHostResolvConf = lib.mkForce false;
        };
        services.resolved.enable = true;
        system.stateVersion = "24.11";
      };
    };
  };
}
