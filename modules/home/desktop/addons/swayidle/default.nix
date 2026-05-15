{
  options,
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.desktop.addons.swayidle;

  lockScript = pkgs.writeShellScript "lock-screen" ''
    WALLPAPER=$(${pkgs.gnugrep}/bin/grep '^wallpaper = ' "$HOME/.config/waypaper/config.ini" 2>/dev/null | ${pkgs.coreutils}/bin/cut -d' ' -f3-)
    if [ -z "$WALLPAPER" ] || [ ! -f "$WALLPAPER" ]; then
      WALLPAPER="${config.custom.desktop.addons.wallpaper}"
    fi
    exec ${pkgs.swaylock-effects}/bin/swaylock -fF --image "$WALLPAPER"
  '';
in
{
  options.custom.desktop.addons.swayidle = with types; {
    enable = mkBoolOpt false "Whether to enable the swayidle";
  };

  config = mkIf cfg.enable {
    services.swayidle = {
      enable = true;

      events = [
        {
          event = "lock";
          command = "${lockScript}";
        }
        {
          event = "after-resume";
          command = "${pkgs.hyprland}/bin/hyprctl dispatch dpms on";
        }
        {
          event = "before-sleep";
          command = "${lockScript}";
        }
      ];
      # 5 min lock, 10min turn the screen off, 20 min suspend
      timeouts = [
        {
          timeout = 300;
          command = "${lockScript}";
        }
        {
          timeout = 600;
          command = "${pkgs.hyprland}/bin/hyprctl dispatch dpms off";
          resumeCommand = "${pkgs.hyprland}/bin/hyprctl dispatch dpms on";
        }
        {
          timeout = 1200;
          command = "${pkgs.systemd}/bin/systemctl suspend";
        }
      ];
    };
  };
}
