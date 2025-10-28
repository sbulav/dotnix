{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkIf types;
  inherit (lib.custom) mkBoolOpt mkOpt;

  cfg = config.custom.desktop.addons.hypridle;

  hyprctl = "${lib.getExe' config.wayland.windowManager.hyprland.package "hyprctl"}";
  swaylock = "${pkgs.swaylock-effects}/bin/swaylock";
  systemctl = "${pkgs.systemd}/bin/systemctl";

  laptopListeners = [
    {
      timeout = 300;
      on-timeout = "${swaylock} -fF";
    }
    {
      timeout = 600;
      on-timeout = "${hyprctl} dispatch dpms off";
      on-resume = "${hyprctl} dispatch dpms on";
    }
    {
      timeout = 1200;
      on-timeout = "${systemctl} suspend";
      on-resume = "${hyprctl} dispatch dpms on";
    }
  ];

  pcListeners = [
    {
      timeout = 600;
      on-timeout = "${swaylock} -fF";
    }
    {
      timeout = 900;
      on-timeout = "${hyprctl} dispatch dpms off";
      on-resume = "${hyprctl} dispatch dpms on";
    }
  ];

  listenerConfig =
    if cfg.profile == "laptop"
    then laptopListeners
    else pcListeners;
in {
  options.custom.desktop.addons.hypridle = {
    enable = mkBoolOpt false "Whether to enable hypridle in the desktop environment.";

    profile = mkOpt (types.enum ["laptop" "pc"]) "laptop" "Power management profile for hypridle.";
  };

  config = mkIf cfg.enable {
    services.hypridle = {
      enable = true;

      settings = {
        general = {
          lock_cmd = "${swaylock} -fF";
          ignore_dbus_inhibit = false;
          after_sleep_cmd = "${hyprctl} dispatch dpms on";
        };

        listener = listenerConfig;
      };
    };
  };
}
