{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.custom; let
  cfg = config.${namespace}.containers.ups;
in {
  options.${namespace}.containers.ups = with types; {
    enable = mkBoolOpt false "Enable UPS monitoring";
    driver = mkOpt str "huawei-ups2000" "Driver to use to connect to UPS";
    port = mkOpt str "/dev/ttyUSB0" "Port to connect";
  };

  config = mkIf cfg.enable {
    # Enable and configure UPS monitoring
    power.ups = {
      enable = true;
      # This mode address a local only configuration, with 1 UPS protecting the
      # local system. This implies to start the 3 NUT layers (driver, upsd and
      # upsmon) and the matching configuration files. This mode can also
      # address UPS redundancy.
      mode = "standalone";

      ups.ups = {
        # find your driver here:
        # https://networkupstools.org/docs/man/usbhid-ups.html
        driver = cfg.driver;
        description = "Huawei UPS2000-G1KRTS";
        port = cfg.port;
        directives = [
          "offdelay = 60"
          "ondelay = 120"
        ];
        # this option is not valid for usbhid-ups
        maxStartDelay = null;
      };

      maxStartDelay = 10;
      # TODO: this  looks like a workaround or bug in check logic
      upsmon.settings = {
        MINSUPPLIES = 0;
      };
    };
  };
}
