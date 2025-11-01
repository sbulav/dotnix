{
  options,
  config,
  lib,
  pkgs,
  ...
} @ args:
with lib;
with lib.custom;
let
  cfg = config.custom.desktop.stylix;
  # osConfig is provided when this module runs in home-manager context under NixOS
  # Check if osConfig exists in the args
  isSystemLevel = !(args ? osConfig);
in
{
  options.custom.desktop.stylix = with types; {
    enable = mkBoolOpt false "Enable centralized Stylix theming";

    theme = mkOpt str "cyberdream" "Theme to use (cyberdream, catppuccin-mocha)";

    wallpaper = mkOpt (nullOr path) null "Wallpaper path for color extraction";

    fonts = {
      monospace = {
        package = mkOpt package pkgs.nerd-fonts.fira-code "Monospace font package";
        name = mkOpt str "FiraCode Nerd Font" "Monospace font name";
      };

      sansSerif = {
        package = mkOpt package pkgs.nerd-fonts.caskaydia-cove "Sans-serif font package";
        name = mkOpt str "CaskaydiaCove Nerd Font" "Sans-serif font name";
      };

      sizes = {
        terminal = mkOpt int 12 "Terminal font size";
        applications = mkOpt int 11 "Application font size";
        desktop = mkOpt int 10 "Desktop/panel font size";
      };
    };

    cursor = {
      package = mkOpt package pkgs.bibata-cursors "Cursor theme package";
      name = mkOpt str "Bibata-Modern-Classic" "Cursor theme name";
      size = mkOpt int 24 "Cursor size";
    };

    iconTheme = {
      package = mkOpt package pkgs.papirus-icon-theme "Icon theme package";
      name = mkOpt str "Papirus-Dark" "Icon theme name";
    };
  };

  config = mkMerge [
    # System-level stylix configuration
    (mkIf (cfg.enable && isSystemLevel) {
      stylix = {
        enable = true;
        image = cfg.wallpaper;

      base16Scheme = mkIf (cfg.theme == "cyberdream") {
        base00 = "0f1113";
        base01 = "191d22";
        base02 = "1f252b";
        base03 = "2b323a";
        base04 = "97a4b6";
        base05 = "e6edf3";
        base06 = "c1cad6";
        base07 = "ffffff";
        base08 = "ff6b82";
        base09 = "ffb86b";
        base0A = "ffd76b";
        base0B = "78f093";
        base0C = "5ef1ff";
        base0D = "5ea1ff";
        base0E = "bd5eff";
        base0F = "ff5ef1";
      };

      fonts = {
        monospace = {
          package = cfg.fonts.monospace.package;
          name = cfg.fonts.monospace.name;
        };
        sansSerif = {
          package = cfg.fonts.sansSerif.package;
          name = cfg.fonts.sansSerif.name;
        };
        serif = cfg.fonts.sansSerif;

        sizes = {
          terminal = cfg.fonts.sizes.terminal;
          applications = cfg.fonts.sizes.applications;
          desktop = cfg.fonts.sizes.desktop;
        };
      };

      cursor = {
        package = cfg.cursor.package;
        name = cfg.cursor.name;
        size = cfg.cursor.size;
      };

        targets = {
          gtk.enable = mkDefault true;
          gnome.enable = mkDefault false;
        };
      };
    })
    
    # Home-manager level: disable stylix to prevent duplicate base16 calculation
    # The system-level stylix config will still apply to home-manager apps via environment
    (mkIf (cfg.enable && !isSystemLevel) {
      stylix.enable = mkForce false;
    })
  ];
}
