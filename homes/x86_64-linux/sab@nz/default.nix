{
  lib,
  config,
  inputs,
  pkgs,
  ...
}:
with lib.custom; let
  wallpapers = inputs.wallpapers-nix.packages.${pkgs.system}.full;
in {
  custom = {
    user = {
      enable = true;
      name = config.snowfallorg.user.name;
    };

    desktop = {
      hyprland = enabled;
      addons = {
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
        wallpaper = "${wallpapers}/share/wallpapers/unorganized/left.jpg";

        waypaper = {
          enable = true;
          wallpaperDirectory = "${wallpapers}/share/wallpapers";
        };
      };
    };

    apps = {
      obsidian = enabled;
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
      gh = enabled;
      git = enabled;
      direnv = disabled;
      k9s = enabled;
    };
    security = {
      rbw = enabled;
      vault = enabled;
      openconnect = enabled;
      sops = {
        enable = true;
        defaultSopsFile = lib.snowfall.fs.get-file "secrets/sab/default.yaml";
        sshKeyPaths = ["${config.home.homeDirectory}/.ssh/id_ed25519"];
      };
    };
  };

  sops.secrets = {
    env_credentials = {
      sopsFile = lib.snowfall.fs.get-file "secrets/sab/default.yaml";
      path = "${config.home.homeDirectory}/.ssh/sops-env-credentials";
    };
  };
  home.stateVersion = "23.11";
}
