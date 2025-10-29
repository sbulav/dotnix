{ options, config, lib, pkgs, ... }:
let
  inherit (lib) mkIf;
  inherit (lib.custom) mkBoolOpt;
  cfg = config.custom.desktop.addons.gtk;
  cyberdreamCss = builtins.readFile ./cyberdream.css;
in {
  options.custom.desktop.addons.gtk = {
    enable = mkBoolOpt false "Whether to customize GTK and apply themes.";

    home.config = mkIf cfg.enable {
      gtk = {
        enable = true;

        theme = {
          name = "Adwaita-dark";
          package = pkgs.gnome.adwaita-icon-theme;
        };
        iconTheme = {
          name = "Adwaita";
          package = pkgs.gnome.adwaita-icon-theme;
        };
        cursorTheme = {
          name = "Adwaita";
          package = pkgs.gnome.adwaita-icon-theme;
        };

        font.name = "System-ui Regular";
        font.size = 11;

        gtk3.extraCss = cyberdreamCss;
        gtk4.extraCss = cyberdreamCss;
      };
    };
  };
}
