{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.custom; let
  cfg = config.${namespace}.containers.prometheus;
in {
  options.${namespace}.containers.prometheus = with types; {
    enable = mkBoolOpt false "Enable the Prometheus monitoring service ;";
    host = mkOpt str "prometheus.sbulav.ru" "The host to serve prometheus on";
  };

  imports = [
    (import ../shared/shared-traefik-route.nix
      {
        app = "prometheus";
        host = "${cfg.host}";
        # url = "http://${cfg.localAddress}:9090";
        url = "http://127.0.0.1:9090";
        route_enabled = cfg.enable;
        middlewares = ["secure-headers" "allow-lan"];
      })
    (import ../shared/shared-adguard-dns-rewrite.nix
      {
        host = "${cfg.host}";
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
          # enabledCollectors = ["systemd"];
          enable = true;
        };
        smartctl = {
          enable = true;
          # TODO: make this dynamic or pass via options
          devices = [
            "/dev/nvme0n1"
            "/dev/sda"
            "/dev/sdb"
            "/dev/sdc"
            "/dev/sdd"
          ];
        };
      };

      # Ingest the published nodes
      scrapeConfigs = let
        nodesScrapeConfig = {
          job_name = "nodes";
          static_configs = let
            baseTargets = [
              "127.0.0.1:3021" # Node exporter
              "127.0.0.1:9633" # Smartctl exporter
            ];

            autheliaTarget =
              if config.${namespace}.containers.authelia.enable
              then ["${config.${namespace}.containers.authelia.localAddress}:9959"]
              else [];
          in [
            {
              targets = baseTargets ++ autheliaTarget;
            }
          ];
        };
      in [nodesScrapeConfig];
    };
  };
}
