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
      instance = name;
      role = hostCfg.role;
    }
    // hostCfg.labels;

  localNodesScrapeConfig =
    if currentHost != null then
      let
        baseTargets =
          optional currentHost.exporters.node.enable "127.0.0.1:${toString currentHost.exporters.node.port}"
          ++ optional currentHost.exporters.smartctl.enable "127.0.0.1:${toString currentHost.exporters.smartctl.port}";

        autheliaTarget =
          if config.${namespace}.containers.authelia.enable then
            [ "${config.${namespace}.containers.authelia.localAddress}:9959" ]
          else
            [ ];
      in
      optional ((baseTargets ++ autheliaTarget) != [ ]) {
        job_name = "nodes";
        static_configs = [
          {
            targets = baseTargets ++ autheliaTarget;
            labels = mkTargetLabels hostName currentHost;
          }
        ];
      }
    else
      let
        baseTargets = [
          "127.0.0.1:3021"
          "127.0.0.1:9633"
        ];

        autheliaTarget =
          if config.${namespace}.containers.authelia.enable then
            [ "${config.${namespace}.containers.authelia.localAddress}:9959" ]
          else
            [ ];
      in
      [
        {
          job_name = "nodes";
          static_configs = [
            {
              targets = baseTargets ++ autheliaTarget;
            }
          ];
        }
      ];

  localNutScrapeConfig =
    if currentHost != null && currentHost.exporters.nut.enable then
      [
        {
          job_name = "nut";
          metrics_path = currentHost.exporters.nut.metricsPath;
          static_configs = [
            {
              targets = [ "127.0.0.1:${toString currentHost.exporters.nut.port}" ];
              labels = mkTargetLabels hostName currentHost;
            }
          ];
        }
      ]
    else
      optional config.${namespace}.containers.ups.enable {
        job_name = "nut";
        metrics_path = "/ups_metrics";
        static_configs = [
          {
            targets = [ "127.0.0.1:9199" ];
          }
        ];
      };

  remoteScrapeConfigs =
    mapAttrsToList
      (
        name: hostCfg:
        let
          targets =
            optional hostCfg.exporters.node.enable "${hostCfg.address}:${toString hostCfg.exporters.node.port}"
            ++ optional hostCfg.exporters.smartctl.enable "${hostCfg.address}:${toString hostCfg.exporters.smartctl.port}";
        in
        {
          job_name = name;
          static_configs = [
            {
              inherit targets;
              labels = mkTargetLabels name hostCfg;
            }
          ];
        }
      )
      (
        filterAttrs (
          _: hostCfg: hostCfg.exporters.node.enable || hostCfg.exporters.smartctl.enable
        ) remoteHosts
      );
in
{
  options.${namespace}.containers.prometheus = with types; {
    enable = mkBoolOpt false "Enable the Prometheus monitoring service ;";
    host = mkOpt str "prometheus.sbulav.ru" "The host to serve prometheus on";
    smartctl_devices = mkOpt (listOf str) [ ] "List of devices to monitor, in the format ['/dev/sda']";
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
      scrapeConfigs = localNodesScrapeConfig ++ localNutScrapeConfig ++ remoteScrapeConfigs;
    };
  };
}
