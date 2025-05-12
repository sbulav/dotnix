{
  lib,
  config,
  ...
}:
with lib.custom; {
  custom = {
    user = {
      enable = true;
      name = config.snowfallorg.user.name;
    };
    apps = {
      obsidian = enabled;
      zoom-us = disabled;
      ktalk = enabled;
    };

    cli-apps = {
      argocd = enabled;
      atuin = enabled;
      bottom = enabled;
      home-manager = enabled;
      neovim = enabled;
      yazi = enabled;
    };

    tools = {
      bat = enabled;
      gh = enabled;
      git = enabled;
      k9s = enabled;
      opentofu = enabled;
      tea = enabled;
    };

    desktop = {
      addons = {
        wezterm = enabled;
      };
    };
    security = {
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
  home.sessionPath = [
    "$HOME/bin"
  ];

  home.stateVersion = "24.05";
}
