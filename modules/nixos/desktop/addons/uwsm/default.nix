{
  config,
  lib,
  namespace,
  ...
}:
let
  inherit (lib) mkIf;
  inherit (lib.${namespace}) mkBoolOpt;

  cfg = config.${namespace}.desktop.addons.uwsm;
in
{
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
          # Launch via start-hyprland (Hyprland's official entrypoint) rather
          # than the raw Hyprland binary. Hyprland 0.55+ warns at startup
          # ("launched without start-hyprland") whenever its process is started
          # by execing the bare binary; start-hyprland sets up the session
          # correctly and silences that warning.
          binPath = "/run/current-system/sw/bin/start-hyprland";
        };
      };
    };
    services = {
      displayManager.defaultSession = "hyprland-uwsm";
    };
  };
}
