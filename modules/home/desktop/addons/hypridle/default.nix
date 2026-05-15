{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf types;
  inherit (lib.custom) mkBoolOpt mkOpt;

  cfg = config.custom.desktop.addons.hypridle;

  hyprctl = "${lib.getExe' config.wayland.windowManager.hyprland.package "hyprctl"}";
  systemctl = "${pkgs.systemd}/bin/systemctl";

  lockScript = pkgs.writeShellScript "lock-screen" ''
    WALLPAPER=$(${pkgs.gnugrep}/bin/grep '^wallpaper = ' "$HOME/.config/waypaper/config.ini" 2>/dev/null | ${pkgs.coreutils}/bin/cut -d' ' -f3-)
    if [ -z "$WALLPAPER" ] || [ ! -f "$WALLPAPER" ]; then
      WALLPAPER="${config.custom.desktop.addons.wallpaper}"
    fi
    exec ${pkgs.swaylock-effects}/bin/swaylock -fF --image "$WALLPAPER"
  '';

  laptopListeners = [
    {
      timeout = 300;
      on-timeout = "${lockScript}";
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
      on-timeout = "${lockScript}";
    }
    {
      timeout = 900;
      on-timeout = "${hyprctl} dispatch dpms off";
      on-resume = "${hyprctl} dispatch dpms on";
    }
  ];

  listenerConfig = if cfg.profile == "laptop" then laptopListeners else pcListeners;
in
{
  options.custom.desktop.addons.hypridle = {
    enable = mkBoolOpt false "Whether to enable hypridle in the desktop environment.";

    profile = mkOpt (types.enum [
      "laptop"
      "pc"
    ]) "laptop" "Power management profile for hypridle.";
  };

  config = mkIf cfg.enable {
    services.hypridle = {
      enable = true;

      settings = {
        general = {
          lock_cmd = "${lockScript}";
          ignore_dbus_inhibit = false;
          after_sleep_cmd = "${hyprctl} dispatch dpms on";
        };

        listener = listenerConfig;
      };
    };
  };
}
