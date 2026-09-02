{
  lib,
  inputs,
  pkgs,
  ...
}:
with lib.custom;
let
  wallpapers = inputs.wallpapers-nix.packages.${pkgs.stdenv.hostPlatform.system}.full;
in
{
  custom = {
    user = {
      enable = true;
    };

    desktop = {
      hyprland = {
        enable = true;
        monitors = [
          "eDP-1,1920x1080@60,0x0,1.5"
        ];
      };
      addons = {
        system-polish = {
          enable = true;
          clamshell = {
            enable = true;
            internalOutput = "eDP-1";
            mode = "1920x1080@60";
            position = "0x0";
            scale = "1.5";
          };
        };
        gtk = enabled;
        kitty = disabled;
        # Noctalia owns bar, notifications, launcher, session menu, wallpaper
        # engine, lock and idle (the old waybar/mako/rofi/wlogout/hyprpaper/
        # waypaper/swaylock/hypridle stack is gone from the repo).
        noctalia = {
          enable = true;
          settings = {
            # Same picker directory waypaper used; the default wallpaper still
            # flows through the shared addons.wallpaper option below.
            wallpaper.directory = "${wallpapers}/share/wallpapers";
            # Parity with the old hypridle "laptop" profile: lock at 5 min,
            # screen off at 10 min, suspend at 20 min. Complete entries only —
            # noctalia drops partial [idle.behavior.*] tables.
            idle.behavior = {
              lock = {
                enabled = true;
                timeout = 300;
                action = "lock";
              };
              screen-off = {
                enabled = true;
                timeout = 600;
                action = "screen_off";
              };
              suspend = {
                enabled = true;
                timeout = 1200;
                action = "suspend";
              };
            };
            # Laptop with a backlight — keep the brightness OSD the module
            # default turns off for the desktop host.
            osd.kinds.brightness = true;
          };
        };
        hypr-scale = enabled;
        wezterm = enabled;
        "wlr-which-key" = enabled;
        screenshot = enabled;
        woomer = enabled;
        wallpaper = "${wallpapers}/share/wallpapers/unorganized/vu_meter_code_neon.png";
      };
    };

    ai = {
      opencode = enabled;
      claude = enabled;
      mcp-k8s-go = enabled;
    };

    apps = {
      obsidian = enabled;
      ktalk = enabled;
    };

    cli-apps = {
      argocd = enabled;
      atuin = enabled;
      bottom = enabled;
      fastfetch = enabled;
      herdr = enabled;
      home-manager = enabled;
      yazi = enabled;
    };
    tools = {
      nix = enabled; # override Determinate's flaky install.determinate.systems cache
      direnv = disabled;
      gh = enabled;
      git = enabled;
      k9s = enabled;
      opentofu = enabled;
      yandex-cloud = enabled;
      tea = enabled;
      sqlite-jira = enabled;
    };
    security = {
      rbw = enabled;
      vault = enabled;
      openconnect = {
        enable = true;
        routes.lanGateway = "192.168.90.1";
      };
      sops = {
        enable = true;
        # Shared module auto-resolves to secrets/sab/default.yaml
        commonSecrets.enableCredentials = true;
        profile = "home";
      };
    };
  };

  # env_credentials now handled by commonSecrets.enableCredentials = true
  home.stateVersion = "25.11";
}
