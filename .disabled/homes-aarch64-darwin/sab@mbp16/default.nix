{
  lib,
  config,
  ...
}:
with lib.custom;
{
  custom = {
    user = {
      enable = true;
      name = config.snowfallorg.user.name;
    };
    ai = {
      opencode = enabled;
      mcp-k8s-go = enabled;
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
        # Shared module auto-resolves to secrets/sab/default.yaml
        commonSecrets.enableCredentials = true;
        # Darwin SOPS works normally now - no fallback needed
      };
    };
  };

  # env_credentials now handled by commonSecrets.enableCredentials = true
  home.sessionPath = [
    "$HOME/bin"
  ];

  home.stateVersion = "25.11";
}
