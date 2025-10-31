{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.${namespace}.services.prometheus-exporters;
in
{
  options.${namespace}.services.prometheus-exporters = with types; {
    enable = mkBoolOpt false "Enable Prometheus exporters for monitoring";

    node = {
      enable = mkBoolOpt true "Enable Node exporter (CPU, memory, disk, network)";
      port = mkOpt int 9100 "Port for Node exporter";
      openFirewall = mkBoolOpt false "Open firewall for remote scraping";
    };

    smartctl = {
      enable = mkBoolOpt false "Enable Smartctl exporter (disk health)";
      port = mkOpt int 9633 "Port for Smartctl exporter";
      openFirewall = mkBoolOpt false "Open firewall for remote scraping";
      devices = mkOpt (listOf str) [ ] "List of devices to monitor, e.g., ['/dev/nvme0n1']";
    };
  };

  config = mkIf cfg.enable {
    services.prometheus.exporters = mkMerge [
      (mkIf cfg.node.enable {
        node = {
          enable = true;
          port = cfg.node.port;
          openFirewall = cfg.node.openFirewall;
        };
      })

      (mkIf cfg.smartctl.enable {
        smartctl = {
          enable = true;
          port = cfg.smartctl.port;
          openFirewall = cfg.smartctl.openFirewall;
          devices = cfg.smartctl.devices;
        };
      })
    ];
  };
}
