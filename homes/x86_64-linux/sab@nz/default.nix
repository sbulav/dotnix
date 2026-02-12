{
  lib,
  config,
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
      name = config.snowfallorg.user.name;
    };

    desktop = {
      hyprland = {
        enable = true;
        monitors = [
          ",preferred,auto,auto"
        ];
      };
      addons = {
        gtk = enabled;
        hyprpaper = enabled;
        mako = enabled;
        rofi = enabled;
        kitty = disabled;
        swaylock = enabled;
        hypridle = enabled;
        waybar = enabled;
        wlogout = enabled;
        hyprlock = disabled;
        wezterm = enabled;
        "wlr-which-key" = enabled;
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
      yandex-cloud = enabled;
      tea = enabled;
      sqlite-jira = enabled;
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
  home.stateVersion = "25.11";
}
