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
      home-manager = enabled;
      yazi = enabled;
    };
    tools = {
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
  home.stateVersion = "24.11";
}
