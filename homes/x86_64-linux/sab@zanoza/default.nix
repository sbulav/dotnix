{
  lib,
  config,
  inputs,
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
      herdr = enabled;
      herdr-remote = {
        enable = true;
        # Traefik and Authelia on zanoza provide the public auth layer.
        enableTokenAuth = false;
        autoStart = true;
        remotes = [
          "mz"
          "192.168.92.136"
          "192.168.92.143"
        ];
      };
      home-manager = enabled;
      yazi = enabled;
    };
    tools = {
      nix = enabled; # override Determinate's flaky install.determinate.systems cache
      gh = disabled;
      git = enabled;
      direnv = disabled;
    };
    security = {
      rbw = disabled;
      vault = disabled;
      sops = {
        enable = true;
        # Shared module auto-resolves to secrets/sab/default.yaml
        # No common secrets needed for this minimal config
      };
    };
  };
  home.stateVersion = "25.11";
}
