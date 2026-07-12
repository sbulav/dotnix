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
        # Dedicated token-authenticated relay for the native Android app.
        enableMobileRelay = true;
        autoStart = true;
        # Only live SSH targets. Dead remotes block herdr-relay's asyncio loop
        # (synchronous ssh with ConnectTimeout=5) for tens of seconds per poll,
        # which freezes WebSocket broadcasts and makes agents "disappear".
        remotes = [
          "192.168.92.136" # mba13 (current DHCP)
        ];
        presets = [
          {
            id = "dotnix-claude-opus";
            label = "dotnix · Claude · Opus";
            agent = "claude";
            model = "opus";
            hosts.mba13 = {
              cwd = "/Users/sab/dotnix";
              target = "192.168.92.136";
            };
          }
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
