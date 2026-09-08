{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
let
  inherit (lib) mkIf optional optionals;
  inherit (lib.${namespace}) mkBoolOpt;

  cfg = config.hardware.sensors;
in
{
  options.hardware.sensors = {
    enable = mkBoolOpt false "Whether or not to expose motherboard fan/temperature sensors.";
    nct6687d = mkBoolOpt false ''
      Load the out-of-tree nct6687 driver. MSI boards drive their fan headers
      through the NCT6687D embedded controller, which the in-tree nct6683
      driver refuses to bind to, so without this `sensors` shows no fan RPM,
      PWM duty, or board temperatures at all.
    '';
    liquidctl = mkBoolOpt false ''
      Install liquidctl with its udev rules so the logged-in user can read the
      AIO pump speed and liquid temperature without sudo.
    '';
  };

  config = mkIf cfg.enable {
    boot = {
      extraModulePackages = optional cfg.nct6687d config.boot.kernelPackages.nct6687d;
      kernelModules = optional cfg.nct6687d "nct6687";
    };

    environment.systemPackages = [ pkgs.lm_sensors ] ++ optionals cfg.liquidctl [ pkgs.liquidctl ];

    services.udev.packages = optionals cfg.liquidctl [ pkgs.liquidctl ];
  };
}
