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
    scrapeConfigs = mkOpt (listOf attrs) [ ] "Explicit exporter jobs, with host labels";
  };
  config = mkIf cfg.enable {
    custom.containers.traefik.routes.prometheus = mkIf cfg.publishWeb {
      host = cfg.host;
      url = "http://127.0.0.1:9090";
      middlewares = [
        "secure-headers"
        "allow-lan"
      ];
    };
    services.prometheus = {
      enable = true;
      # Grafana's container and zanoza's ingress use the host interfaces.
      listenAddress = "0.0.0.0";
      port = 9090;
      retentionTime = "15d";
      scrapeConfigs = cfg.scrapeConfigs;
    };
  };
}
