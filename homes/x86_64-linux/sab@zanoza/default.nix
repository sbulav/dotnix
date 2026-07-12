{
  lib,
  config,
  inputs,
  pkgs,
  ...
}:
let
  mobileHost = {
    target = "192.168.92.136";
  };
  launchRepositories = [
    {
      id = "dotnix";
      label = "dotnix";
      cwd = "/Users/sab/dotnix";
    }
    {
      id = "herdr-mobile";
      label = "Herdr Mobile";
      cwd = "/Users/sab/git_priv/herdr-mobile";
    }
  ];
  launchHarnesses = [
    {
      id = "claude-opus";
      label = "Claude · Opus";
      agent = "claude";
      model = "opus";
    }
    {
      id = "claude-sonnet";
      label = "Claude · Sonnet";
      agent = "claude";
      model = "sonnet";
    }
    {
      id = "opencode-opus";
      label = "OpenCode · Opus 4.8";
      agent = "opencode";
      model = "anthropic/claude-opus-4-8";
    }
    {
      id = "opencode-sonnet";
      label = "OpenCode · Sonnet 4.6";
      agent = "opencode";
      model = "anthropic/claude-sonnet-4-6";
    }
    {
      id = "opencode-grok45";
      label = "OpenCode · Grok 4.5";
      agent = "opencode";
      model = "hhdev-grok/grok-4.5";
    }
    {
      id = "opencode-glm52";
      label = "OpenCode · GLM 5.2";
      agent = "opencode";
      model = "hhdev-glm5-fp8/zai-org/GLM-5.2-FP8";
    }
    {
      id = "codex-gpt56";
      label = "Codex · GPT-5.6 Sol";
      agent = "codex";
      model = "gpt-5.6-sol";
    }
  ];
in
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
        # The relay keeps a flat allowlist; the mobile app presents these as
        # independent Repository → Harness → Model → Host selectors.
        presets = lib.concatMap (
          repository:
          map (harness: {
            id = "${repository.id}-${harness.id}";
            label = "${repository.label} · ${harness.label}";
            repository = repository.id;
            inherit (harness) agent model;
            hosts.mba13 = mobileHost // {
              inherit (repository) cwd;
            };
          }) launchHarnesses
        ) launchRepositories;
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
