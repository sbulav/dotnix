{
  options,
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom; let
  cfg = config.custom.desktop.addons.regreet;
  wallpaper = options.system.wallpaper.value;
  dbus-run-session = lib.getExe' pkgs.dbus "dbus-run-session";
  hyprland = lib.getExe config.programs.hyprland.package;
  hyprland-conf = pkgs.writeText "greetd-hyprland.conf" ''
    bind = SUPER SHIFT, E, killactive,
    misc {
        disable_hyprland_logo = true
    }
    animations {
        enabled = false
    }
    exec-once = ${lib.getExe config.programs.regreet.package}; hyprctl dispatch exit
  '';
in {
  options.custom.desktop.addons.regreet = with types; {
    enable = mkBoolOpt false "Whether to enable the regreet display manager";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      # theme packages
      (catppuccin-gtk.override {
        accents = ["mauve"];
        size = "compact";
        variant = "mocha";
      })
      bibata-cursors
      papirus-icon-theme
    ];
    programs.regreet = {
      enable = true;

      cursorTheme.name = "Bibata-Modern-Classic";
      font.name = "FiraCode Nerd Font Regular";
      font.size = 12;
      iconTheme.name = "Papirus-Dark";
      theme.name = "Catppuccin-Mocha-Compact-Mauve-dark";

      settings = {
        env = {
          STATE_DIR = "/var/cache/regreet";
        };

        background = {
          path = wallpaper;
          fit = "Cover";
        };
      };
    };
    systemd.tmpfiles.settings."10-regreet" = let
      defaultConfig = {
        user = "greeter";
        group = config.users.users.${config.services.greetd.settings.default_session.user}.group;
        mode = "0755";
      };
    in {
      "/var/lib/regreet".d = defaultConfig;
    };
    security.pam.services.greetd.enableGnomeKeyring = true;
    services.greetd.settings.default_session.command = "${dbus-run-session} ${hyprland} --config ${hyprland-conf} &> /dev/null";
  };
}
