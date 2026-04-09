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
      staticConfigs,
    }:
    {
      job_name = jobName;
      static_configs = staticConfigs;
    }
    // optionalAttrs (metricsPath != null) {
      metrics_path = metricsPath;
    };

  mkStaticConfig =
    {
      targets,
      labels ? { },
    }:
    {
      inherit targets labels;
    };

  mkInventoryStaticConfigs =
    exporterName:
    flatten (
      mapAttrsToList (
        name: hostCfg:
        optional hostCfg.exporters.${exporterName}.enable (mkStaticConfig {
          targets = [ "${hostCfg.address}:${toString hostCfg.exporters.${exporterName}.port}" ];
          labels = mkTargetLabels name hostCfg;
        })
      ) remoteHosts
    );

  nodeStaticConfigs =
    (
      if currentHost != null && currentHost.exporters.node.enable then
        [
          (mkStaticConfig {
            targets = [ "127.0.0.1:${toString currentHost.exporters.node.port}" ];
            labels = mkTargetLabels hostName currentHost;
          })
        ]
      else
        [
          (mkStaticConfig {
            targets = [ "127.0.0.1:3021" ];
            labels = { host = hostName; };
          })
        ]
    )
    ++ mkInventoryStaticConfigs "node";

  smartctlStaticConfigs =
    (
      if currentHost != null && currentHost.exporters.smartctl.enable then
        [
          (mkStaticConfig {
            targets = [ "127.0.0.1:${toString currentHost.exporters.smartctl.port}" ];
            labels = mkTargetLabels hostName currentHost;
          })
        ]
      else
        [
          (mkStaticConfig {
            targets = [ "127.0.0.1:9633" ];
            labels = { host = hostName; };
          })
        ]
    )
    ++ mkInventoryStaticConfigs "smartctl";

  nutStaticConfigs =
    (
      if currentHost != null then
        optional currentHost.exporters.nut.enable (mkStaticConfig {
          targets = [ "127.0.0.1:${toString currentHost.exporters.nut.port}" ];
          labels = mkTargetLabels hostName currentHost;
        })
      else
        optional config.${namespace}.containers.ups.enable (mkStaticConfig {
          targets = [ "127.0.0.1:9199" ];
        })
    )
    ++ mkInventoryStaticConfigs "nut";

  autheliaStaticConfigs = optional config.${namespace}.containers.authelia.enable (mkStaticConfig {
    targets = [ "${config.${namespace}.containers.authelia.localAddress}:9959" ];
    labels = optionalAttrs (currentHost != null) (mkTargetLabels hostName currentHost);
  });

  localScrapeConfigs = [
    (mkScrapeConfig {
      jobName = "node";
      staticConfigs = nodeStaticConfigs;
    })
    (mkScrapeConfig {
      jobName = "smartctl";
      staticConfigs = smartctlStaticConfigs;
    })
  ]
  ++ optional (nutStaticConfigs != [ ]) (mkScrapeConfig {
    jobName = "nut";
    metricsPath = if currentHost != null then currentHost.exporters.nut.metricsPath else "/ups_metrics";
    staticConfigs = nutStaticConfigs;
  })
  ++ optional (autheliaStaticConfigs != [ ]) (mkScrapeConfig {
    jobName = "authelia";
    staticConfigs = autheliaStaticConfigs;
  });
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
          enable = (currentHost != null && currentHost.exporters.nut.enable) || config.${namespace}.containers.ups.enable;
        };
      };

      # Ingest the published nodes
      scrapeConfigs = localScrapeConfigs;
    };
  };
}
