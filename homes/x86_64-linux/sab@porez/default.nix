{
  lib,
  config,
  inputs,
  pkgs,
  ...
}:
with lib.custom;
let
  wallpapers = inputs.wallpapers-nix.packages.${pkgs.system}.full;
in
{
  custom = {
    user = {
      enable = true;
      name = config.snowfallorg.user.name;
    };

    desktop = {
      hyprland = {
        enable = true;
        monitors = [
          "HDMI-A-1,1920x1080,0x0,1"
          "DP-2,3840x2560@60,1920x0,2"
        ];
        workspaces.monitorBindings = {
          "1" = "DP-2";
          "2" = "DP-2";
          "3" = "DP-2";
          "4" = "DP-2";
          "5" = "DP-2";
          "6" = "DP-2";
          "7" = "HDMI-A-1";
          "8" = "HDMI-A-1";
          "9" = "HDMI-A-1";
        };
        keybindings = {
          copy = "C";
          paste = "V";
          clipboard = "SHIFT C";
        };
      };
      addons = {
        hyprpaper = enabled;
        mako = enabled;
        rofi = enabled;
        kitty = disabled;
        swaylock = enabled;
        hypridle = {
          enable = true;
          profile = "pc";
        };
        waybar = {
          enable = true;
          keyboardName = "kinesis-advantage2-keyboard-1";
        };
        wlogout = enabled;
        hyprlock = disabled;
        wezterm = enabled;
        wallpaper = "${wallpapers}/share/wallpapers/cities/1-osaka-jade-bg.jpg";

        waypaper = {
          enable = true;
          wallpaperDirectory = "${wallpapers}/share/wallpapers";
        };
      };
    };

    ai = {
      opencode = enabled;
      mcp-k8s-go = enabled;
    };

    apps = {
      obsidian = enabled;
      ktalk = enabled;
      libreoffice = enabled;
    };

    cli-apps = {
      argocd = enabled;
      atuin = enabled;
      bottom = enabled;
      fastfetch = enabled;
      home-manager = enabled;
      yazi = enabled;
    };
    tools = {
      direnv = disabled;
      gh = enabled;
      git = enabled;
      k9s = enabled;
      opentofu = enabled;
      yandex-cloud = disabled;
    };
    security = {
      rbw = enabled;
      vault = enabled;
      openconnect = enabled;
      sops = {
        enable = true;
        # Shared module auto-resolves to secrets/sab/default.yaml
        commonSecrets.enableCredentials = true;
        profile = "home";
      };
    };
  };

  # env_credentials now handled by commonSecrets.enableCredentials = true
  home.stateVersion = "24.11";
}
