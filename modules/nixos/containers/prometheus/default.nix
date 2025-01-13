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
        # Provided by node exporter
        # zfs.enable = true;
        smartctl = {
          enable = true;
          devices = [
            "/dev/nvme0n1"
            "/dev/sda"
            "/dev/sdb"
            "/dev/sdc"
            "/dev/sdd"
          ];
        };
      };

      # ingest the published nodes
      scrapeConfigs = [
        {
          job_name = "nodes";
          static_configs = [
            {
              targets = [
                "127.0.0.1:3021" #Node exporer
                # "127.0.0.1:9134" #ZFS exporter
                "127.0.0.1:9633" #Smartctl exporter
              ];
            }
          ];
        }
      ];
    };
  };
}
