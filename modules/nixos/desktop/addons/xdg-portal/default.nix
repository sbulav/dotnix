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
  cfg = config.custom.desktop.addons.xdg-portal;
in
{
  options.custom.desktop.addons.xdg-portal = with types; {
    enable = mkBoolOpt false "Whether or not to add support for xdg portal.";
  };

  config = mkIf cfg.enable {
    xdg = {
      autostart.enable = true;
      portal = {
        enable = true;
        
        extraPortals = with pkgs; [
          xdg-desktop-portal-hyprland
          xdg-desktop-portal-gtk
        ];

        # Configure portal backends explicitly for proper screensharing
        # This is critical for NVIDIA + Hyprland screensharing to work correctly
        config = {
          common = {
            default = [ "gtk" ];
          };
          hyprland = {
            default = [
              "hyprland"
              "gtk"
            ];
            # Use Hyprland portal for screencasting/screenshots
            "org.freedesktop.impl.portal.Screenshot" = [ "hyprland" ];
            "org.freedesktop.impl.portal.ScreenCast" = [ "hyprland" ];
          };
        };

        xdgOpenUsePortal = true;
      };
    };

    # Ensure proper environment for portal integration
    environment.sessionVariables = {
      NIXOS_XDG_OPEN_USE_PORTAL = "1";
    };
  };
}
