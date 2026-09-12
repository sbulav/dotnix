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
    enable = mkBoolOpt false "Enable the Prometheus monitoring service ;";
    host = mkOpt str "prometheus.sbulav.ru" "The host to serve prometheus on";
    smartctl_devices = mkOpt (listOf str) [ ] "List of devices to monitor, in the format ['/dev/sda']";
  };

  imports = [
    (import ../shared/shared-adguard-dns-rewrite.nix {
      host = cfg.host;
      rewrite_enabled = cfg.enable;
    })
  ];

  config = mkIf cfg.enable {
    # Prometheus runs on the host itself, not in a container.
    # NOTE: this list used to be passed as `middlewares` to a helper that only
    # accepted `middleware`, so the route silently fell back to `auth-chain`
    # (issue #48). It is now applied as intended.
    custom.containers.traefik.routes.prometheus = {
      host = cfg.host;
      url = "http://127.0.0.1:9090";
      middlewares = [
        "secure-headers"
        "allow-lan"
      ];
    };

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
          # Binary default is a short list and omits runtime/temperature.
          # Explicit list so the UPS dash + temp alert have the series they need.
          nutVariables = [
            "battery.charge"
            "battery.runtime"
            "battery.runtime.low"
            "battery.voltage"
            "battery.voltage.nominal"
            "input.voltage"
            "input.voltage.nominal"
            "output.voltage"
            "ups.load"
            "ups.status"
            "ups.temperature"
          ];
        };
      };

      # Ingest the published nodes
      scrapeConfigs =
        let
          nutScrapeConfig =
            if config.${namespace}.containers.ups.enable then
              {
                job_name = "nut";
                metrics_path = "/ups_metrics";

                static_configs = [
                  {
                    targets = [ "127.0.0.1:9199" ];
                    # The nut exporter emits no `ups` label, but the NUT dashboard
                    # keys every panel off a $ups variable
                    # (label_values(network_ups_tools_device_info, ups)). Inject a
                    # constant `ups` label matching the NUT ups name so the
                    # variable resolves and the panels render.
                    labels = {
                      ups = "ups";
                    };
                  }
                ];
              }
            else
              { };
          nodesScrapeConfig = {
            job_name = "nodes";
            static_configs =
              let
                baseTargets = [
                  "127.0.0.1:3021" # Node exporter
                  "127.0.0.1:9633" # Smartctl exporter
                ];

                autheliaTarget =
                  if config.${namespace}.containers.authelia.enable then
                    [ "${config.${namespace}.containers.authelia.localAddress}:9959" ]
                  else
                    [ ];
              in
              [
                {
                  targets = baseTargets ++ autheliaTarget;
                }
              ];
          };
        in
        [
          nodesScrapeConfig
          nutScrapeConfig
        ];
    };
  };
}
