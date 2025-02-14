{
  config,
  lib,
  namespace,
  ...
}: let
  inherit (lib) mkIf;
  inherit (lib.${namespace}) mkBoolOpt;

  cfg = config.${namespace}.desktop.addons.uwsm;
in {
  options.${namespace}.desktop.addons.uwsm = {
    # Universal Wayland Session Manager is a recommended way to start Hyprland
    # session on systemd distros.
    enable = mkBoolOpt false "Whether or not to enable uwsm";
  };

  config = mkIf cfg.enable {
    programs.uwsm = {
      enable = true;
      waylandCompositors = {
        hyprland = {
          prettyName = "Hyprland";
          comment = "Hyprland compositor managed by UWSM";
          binPath = "/run/current-system/sw/bin/Hyprland";
        };
      };
    };
    services = {
      displayManager.defaultSession = "hyprland-uwsm";
    };
  };
}
