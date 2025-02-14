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
    games.enable = true;

    desktop = {
      hyprland = enabled;
      addons = {
        hyprpaper = enabled;
        mako = enabled;
        rofi = enabled;
        kitty = disabled;
        swaylock = disabled;
        hypridle = disabled;
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
      obsidian = disabled;
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
      gh = disabled;
      git = enabled;
      direnv = disabled;
      k9s = disabled;
    };
    security = {
      rbw = enabled;
      vault = disabled;
      openconnect = disabled;
      # sops = {
      #   enable = false;
      #   defaultSopsFile = lib.snowfall.fs.get-file "secrets/sab/default.yaml";
      #   sshKeyPaths = ["${config.home.homeDirectory}/.ssh/id_ed25519"];
      # };
    };
  };

  # sops.secrets = {
  #   env_credentials = {
  #     sopsFile = lib.snowfall.fs.get-file "secrets/sab/default.yaml";
  #     path = "${config.home.homeDirectory}/.ssh/sops-env-credentials";
  #   };
  # };
  home.stateVersion = "24.11";
}
