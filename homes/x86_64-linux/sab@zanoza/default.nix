{
  lib,
  inputs,
  pkgs,
  ...
}:
let
  # Claude Code has no machine-readable model listing, so the relay offers
  # exactly what is declared here. Every other harness is enumerated by probing
  # the host, and what is declared for it is ignored.
  claudeModels = [
    {
      id = "opus";
      displayName = "Opus";
    }
    {
      id = "sonnet";
      displayName = "Sonnet";
    }
    {
      id = "haiku";
      displayName = "Haiku";
    }
  ];
  harnesses = [
    {
      id = "claude";
      displayName = "Claude Code";
      modelAliases = claudeModels;
    }
    {
      id = "opencode";
      displayName = "OpenCode";
    }
  ];
in
with lib.custom;
{
  custom = {
    user = {
      enable = true;
    };

    cli-apps = {
      argocd = enabled;
      atuin = enabled;
      bottom = enabled;
      fastfetch = enabled;
      herdr = enabled;
      herdr-remote = {
        enable = true;
        # Authelia still guards the Traefik path, but the relay refuses to start
        # without a token since it gained a mandatory auth gate — the socket can
        # drive a terminal and shut hosts down over SSH, so an unset token is no
        # longer treated as "open". The web app carries the token itself, in its
        # own field rather than in `defaultRelayUrl`, which would bake a secret
        # into the world-readable store path it serves from.
        enableTokenAuth = true;
        # Dedicated token-authenticated relay for the native Android app.
        enableMobileRelay = true;
        autoStart = true;
        # Only list machines that are actually reachable. A host that is down
        # costs one ConnectTimeout=5 per poll cycle, and every host here is
        # polled whether or not anyone is looking at it.
        #
        # This list *is* the catalog: a client sees these hosts, browses their
        # project roots for a folder, and picks from the harnesses discovered
        # on each. Nothing outside a project root can be launched, so a root is
        # the unit of access, not a convenience.
        hosts = [
          {
            id = "mba13";
            displayName = "MacBook Air";
            target = "192.168.92.136"; # current DHCP lease
            # git_priv holds the repositories; dotnix sits outside it and is
            # named directly, which also makes it selectable as a project —
            # a root is browsable *and* startable.
            projectRoots = [
              "/Users/sab/git_priv"
              "/Users/sab/dotnix"
            ];
            inherit harnesses;
          }
          {
            id = "mz";
            displayName = "Workstation";
            target = "mz"; # 192.168.89.200 via split DNS; stable across DHCP
            projectRoots = [
              "/home/sab/dotnix"
              "/home/sab/git_priv/"
            ];
            inherit harnesses;
            wakeMac = "34:5a:60:ba:8e:20";
            # The relay powers a host off with `sudo -n systemctl poweroff`
            # over SSH — the same command since relay 0.7 — and it reaches mz
            # as sab, who holds NOPASSWD sudo there. Verified end-to-end from
            # zanoza (`ssh mz sudo -n true`), so the button is real, not
            # decorative.
            shutdown = true;
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
