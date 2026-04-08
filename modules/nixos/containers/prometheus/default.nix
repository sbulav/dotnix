{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.${namespace}.containers.prometheus;
  hostName = config.networking.hostName;

  inventory = cfg.inventory;

  currentHost = inventory.${hostName} or null;

  remoteHosts = filterAttrs (
    name: hostCfg: name != hostName && hostCfg.enable && (hostCfg.address != "")
  ) inventory;

  mkTargetLabels =
    name: hostCfg:
    {
      host = name;
      role = hostCfg.role;
    }
    // hostCfg.labels;

  mkScrapeConfig =
    {
      jobName,
      metricsPath ? null,
      targets,
      labels ? { },
    }:
    {
      job_name = jobName;
      static_configs = [
        {
          inherit targets labels;
        }
      ];
    }
    // optionalAttrs (metricsPath != null) {
      metrics_path = metricsPath;
    };

  localScrapeConfigs =
    if currentHost != null then
      (optional currentHost.exporters.node.enable (mkScrapeConfig {
        jobName = "node";
        targets = [ "127.0.0.1:${toString currentHost.exporters.node.port}" ];
        labels = mkTargetLabels hostName currentHost;
      }))
      ++ (optional currentHost.exporters.smartctl.enable (mkScrapeConfig {
        jobName = "smartctl";
        targets = [ "127.0.0.1:${toString currentHost.exporters.smartctl.port}" ];
        labels = mkTargetLabels hostName currentHost;
      }))
      ++ (optional currentHost.exporters.nut.enable (mkScrapeConfig {
        jobName = "nut";
        metricsPath = currentHost.exporters.nut.metricsPath;
        targets = [ "127.0.0.1:${toString currentHost.exporters.nut.port}" ];
        labels = mkTargetLabels hostName currentHost;
      }))
      ++ (optional config.${namespace}.containers.authelia.enable (mkScrapeConfig {
        jobName = "authelia";
        targets = [ "${config.${namespace}.containers.authelia.localAddress}:9959" ];
        labels = mkTargetLabels hostName currentHost;
      }))
    else
      [
        (mkScrapeConfig {
          jobName = "node";
          targets = [ "127.0.0.1:3021" ];
        })
        (mkScrapeConfig {
          jobName = "smartctl";
          targets = [ "127.0.0.1:9633" ];
        })
      ]
      ++ optional config.${namespace}.containers.ups.enable (mkScrapeConfig {
        jobName = "nut";
        metricsPath = "/ups_metrics";
        targets = [ "127.0.0.1:9199" ];
      })
      ++ optional config.${namespace}.containers.authelia.enable (mkScrapeConfig {
        jobName = "authelia";
        targets = [ "${config.${namespace}.containers.authelia.localAddress}:9959" ];
      });

  remoteScrapeConfigs = flatten (
    mapAttrsToList (
      name: hostCfg:
      (optional hostCfg.exporters.node.enable (mkScrapeConfig {
        jobName = "node";
        targets = [ "${hostCfg.address}:${toString hostCfg.exporters.node.port}" ];
        labels = mkTargetLabels name hostCfg;
      }))
      ++ (optional hostCfg.exporters.smartctl.enable (mkScrapeConfig {
        jobName = "smartctl";
        targets = [ "${hostCfg.address}:${toString hostCfg.exporters.smartctl.port}" ];
        labels = mkTargetLabels name hostCfg;
      }))
      ++ (optional hostCfg.exporters.nut.enable (mkScrapeConfig {
        jobName = "nut";
        metricsPath = hostCfg.exporters.nut.metricsPath;
        targets = [ "${hostCfg.address}:${toString hostCfg.exporters.nut.port}" ];
        labels = mkTargetLabels name hostCfg;
      }))
    ) remoteHosts
  );
in
{
  options.${namespace}.containers.prometheus = with types; {
    enable = mkBoolOpt false "Enable the Prometheus monitoring service ;";
    host = mkOpt str "prometheus.sbulav.ru" "The host to serve prometheus on";
    smartctl_devices = mkOpt (listOf str) [ ] "List of devices to monitor, in the format ['/dev/sda']";
    scrapeInterval = mkOpt str "30s" "Global Prometheus scrape interval";
    evaluationInterval = mkOpt str "30s" "Global Prometheus evaluation interval";
    retentionTime = mkOpt str "30d" "How long Prometheus should retain metrics";
    externalLabels = mkOpt (attrsOf str) { } "External labels applied to all Prometheus metrics";
    inventory = mkOpt (attrsOf (submodule {
      options = {
        enable = mkBoolOpt true "Whether to include this host in the Prometheus inventory";
        address = mkOpt str "" "Hostname or IP address Prometheus should scrape";
        role = mkOpt str "generic" "Logical role label for this monitored host";
        labels = mkOpt (attrsOf str) { } "Additional labels to attach to scrape targets";

        exporters = {
          node = {
            enable = mkBoolOpt false "Whether node exporter is enabled on this host";
            port = mkOpt int 9100 "Port for node exporter";
          };

          smartctl = {
            enable = mkBoolOpt false "Whether smartctl exporter is enabled on this host";
            port = mkOpt int 9633 "Port for smartctl exporter";
          };

          nut = {
            enable = mkBoolOpt false "Whether NUT exporter is enabled on this host";
            port = mkOpt int 9199 "Port for NUT exporter";
            metricsPath = mkOpt str "/ups_metrics" "Metrics path for the NUT exporter";
          };
        };
      };
    })) { } "Inventory of monitored hosts and their exporters";
  };

  imports = [
    (import ../shared/shared-traefik-route.nix {
      app = "prometheus";
      host = cfg.host;
      # url = "http://${cfg.localAddress}:9090";
      url = "http://127.0.0.1:9090";
      route_enabled = cfg.enable;
      middlewares = [
        "secure-headers"
        "allow-lan"
      ];
    })
    (import ../shared/shared-adguard-dns-rewrite.nix {
      host = cfg.host;
      rewrite_enabled = cfg.enable;
    })
  ];

  config = mkIf cfg.enable {
    services.prometheus = {
      port = 9090;
      enable = true;
      retentionTime = cfg.retentionTime;
      ruleFiles = [
        ./rules/recording.yml
        ./rules/alerts.yml
      ];
      globalConfig = {
        scrape_interval = cfg.scrapeInterval;
        evaluation_interval = cfg.evaluationInterval;
      }
      // optionalAttrs (cfg.externalLabels != { }) {
        external_labels = cfg.externalLabels;
      };

      exporters = {
        node = {
          port = 3021;
          # enabledCollectors = [""];
          enable = true;
        };
        smartctl = {
          enable = true;
          devices = cfg.smartctl_devices;
        };
        nut = {
          enable = true;
        };
      };

      # Ingest the published nodes
      scrapeConfigs = localScrapeConfigs ++ remoteScrapeConfigs;
    };
  };
}
