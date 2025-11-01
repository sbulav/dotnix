{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.desktop.addons.gtk;
in
{
  options.custom.desktop.addons.gtk = with types; {
    enable = mkBoolOpt false "Whether to customize GTK and apply themes.";

    themeName = mkOpt str "Adwaita-dark" "GTK theme name";
    iconThemeName = mkOpt str "Adwaita" "Icon theme name";
    cursorThemeName = mkOpt str "Adwaita" "Cursor theme name";
    cursorSize = mkOpt int 24 "Cursor size";
    fontName = mkOpt str "Sans" "Font name";
    fontSize = mkOpt int 11 "Font size";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      gnome-themes-extra
      adwaita-icon-theme
      gsettings-desktop-schemas
      (catppuccin-gtk.override {
        accents = [ "mauve" ];
        size = "compact";
        variant = "mocha";
      })
    ];

    gtk = {
      enable = true;

      theme = {
        name = cfg.themeName;
        package = pkgs.gnome-themes-extra;
      };

      iconTheme = {
        name = cfg.iconThemeName;
        package = pkgs.adwaita-icon-theme;
      };

      cursorTheme = {
        name = cfg.cursorThemeName;
        package = pkgs.adwaita-icon-theme;
      };

      font = {
        name = cfg.fontName;
        size = cfg.fontSize;
      };

      gtk2.extraConfig = ''
        gtk-application-prefer-dark-theme=1
      '';

      gtk3.extraConfig = {
        gtk-application-prefer-dark-theme = 1;
      };

      gtk4.extraConfig = {
        gtk-application-prefer-dark-theme = 1;
      };
    };

    # Configure dconf/gsettings for GTK theme
    dconf.settings = {
      "org/gnome/desktop/interface" = {
        gtk-theme = cfg.themeName;
        icon-theme = cfg.iconThemeName;
        cursor-theme = cfg.cursorThemeName;
        cursor-size = cfg.cursorSize;
        color-scheme = "prefer-dark";
        font-name = "${cfg.fontName} ${toString cfg.fontSize}";
      };

      "org/gnome/desktop/wm/preferences" = {
        theme = cfg.themeName;
      };
    };

    # XSettings daemon configuration (for X11/XWayland apps)
    xdg.configFile."xsettingsd/xsettingsd.conf".text = ''
      Net/ThemeName "${cfg.themeName}"
      Net/IconThemeName "${cfg.iconThemeName}"
      Gtk/CursorThemeName "${cfg.cursorThemeName}"
      Gtk/CursorThemeSize ${toString cfg.cursorSize}
      Net/EnableEventSounds 1
      EnableInputFeedbackSounds 0
      Xft/Antialias 1
      Xft/Hinting 1
      Xft/HintStyle "hintslight"
      Xft/RGBA "rgb"
      Gtk/ApplicationPreferDarkTheme 1
    '';

    # Qt theme configuration to match GTK
    qt = {
      enable = true;
      platformTheme.name = "adwaita";
      style = {
        name = "adwaita-dark";
        package = pkgs.adwaita-qt;
      };
    };

    # Pointer cursor configuration
    home.pointerCursor = {
      name = cfg.cursorThemeName;
      package = pkgs.adwaita-icon-theme;
      size = cfg.cursorSize;
      gtk.enable = true;
      x11.enable = true;
    };
  };
}
