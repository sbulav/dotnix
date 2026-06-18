{
  config,
  lib,
  pkgs,
  ...
}:
with lib.custom;
{
  custom = {
    user = {
      enable = true;
      name = config.snowfallorg.user.name;
    };

    cli-apps = {
      argocd = enabled;
      atuin = enabled;
      bottom = enabled;
      fastfetch = enabled;
      home-manager = enabled;
      yazi = enabled;
    };

    desktop.addons.wezterm = enabled;

    tools = {
      cli = enabled;
      gh = enabled;
      git = {
        enable = true;
        enableSigning = false;
      };
      k9s = enabled;
      sqlite-jira = enabled;
      tea = enabled;
    };

    security.vault = enabled;
  };

  home = {
    file."Pictures/screenshots/.keep".text = "";
    packages = [ pkgs.neovim ];
    sessionPath = [ "$HOME/bin" ];
  };

  xdg.configFile = {
    fish = {
      source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/fish";
      force = true;
    };

    nvim = {
      source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/nvim";
      force = true;
    };
  };

  # ======================== DO NOT CHANGE THIS ========================
  home.stateVersion = "26.05";
  # ======================== DO NOT CHANGE THIS ========================
}
