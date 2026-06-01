{
  config,
  lib,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.desktop.addons.hyprpaper;
  wallpaper = config.custom.desktop.addons.wallpaper;
in
{
  options.custom.desktop.addons.hyprpaper = with types; {
    enable = mkBoolOpt false "Whether to enable the hyprpaper config";
  };

  config = mkIf cfg.enable {
    # hyprpaper 0.8+ rewrote its config format: legacy `preload=` and
    # `wallpaper = monitor,path` are silently ignored. The new format uses
    # hyprlang special categories. home-manager's services.hyprpaper still
    # emits the legacy shape, so override the file directly.
    services.hyprpaper.enable = true;

    xdg.configFile."hypr/hyprpaper.conf".text = ''
      ipc = true

      wallpaper {
        monitor =
        path = ${wallpaper}
        fit_mode = cover
      }
    '';
  };
}
