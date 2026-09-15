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
in
{
  options.${namespace}.containers.prometheus = with types; {
    enable = mkBoolOpt false "Enable the Prometheus monitoring service";
    host = mkOpt str "prometheus.sbulav.ru" "Public Prometheus hostname";
    publishWeb = mkBoolOpt true "Publish a route on this host's Traefik";
    remoteBackend = mkOpt (nullOr str) null ''
      Publish this host's Prometheus route for a Prometheus running elsewhere,
      at this URL. The service itself stays disabled here.'';
    scrapeConfigs = mkOpt (listOf attrs) [ ] "Explicit exporter jobs, with host labels";
  };
  config = mkMerge [
    {
      assertions = [
        {
          assertion = !(cfg.enable && cfg.remoteBackend != null);
          message = "custom.containers.prometheus: remoteBackend points the route away from the Prometheus enabled on this host";
        }
      ];
    }

    # The same route whether Prometheus runs here or on another host.
    (mkIf (cfg.remoteBackend != null || (cfg.enable && cfg.publishWeb)) {
      custom.containers.traefik.routes.prometheus = {
        host = cfg.host;
        url = if cfg.remoteBackend != null then cfg.remoteBackend else "http://127.0.0.1:9090";
        middlewares = [
          "secure-headers"
          "allow-lan"
        ];
      };
    })

    (mkIf cfg.enable {
      services.prometheus = {
        enable = true;
        # Grafana's container and zanoza's ingress use the host interfaces.
        listenAddress = "0.0.0.0";
        port = 9090;
        retentionTime = "15d";
        scrapeConfigs = cfg.scrapeConfigs;
      };
    })
  ];
}
