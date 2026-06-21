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

    ai = {
      claude = enabled;
      mcp-k8s-go = enabled;
      # mcp-grafana is intentionally not enabled on mba13.

      opencode = {
        enable = true;
        # Use direct Anthropic API on mba13 (no corporate gateway)
        settings = {
          model = "anthropic/claude-sonnet-4-6";
          small_model = "anthropic/claude-haiku-4-5-20251001";
          # Add direct Anthropic provider alongside hhdev-* providers
          provider = {
            anthropic = {
              npm = "@ai-sdk/anthropic";
              name = "Anthropic";
              models = {
                "claude-sonnet-4-6" = {
                  name = "Claude Sonnet 4.6";
                };
                "claude-opus-4-8" = {
                  name = "Claude Opus 4.8";
                };
                "claude-haiku-4-5-20251001" = {
                  name = "Claude Haiku 4.5";
                };
              };
            };
          };
        };
      };
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
      direnv = disabled;
      gh = enabled;
      git = {
        enable = true;
        enableSigning = true;
        # Sign with the YubiKey key; gpg-smart-sign swaps in the local fallback
        # key automatically when the YubiKey is not plugged in.
        signingKey = "15DB4B4A58D027CB73D0E911D06334BAEC6DC034";
        gpgProgram = "${pkgs.custom.gpg-smart-sign}/bin/gpg-smart-sign";
      };
      k9s = enabled;
      sqlite-jira = enabled;
      tea = enabled;
    };

    security = {
      gpg = {
        enable = true;
        yubikeyKeyId = "15DB4B4A58D027CB73D0E911D06334BAEC6DC034";
      };
      openconnect = enabled;
      sops = {
        enable = true;
        # Decrypt secrets/sab/default.yaml to ~/.ssh/sops-env-credentials;
        # Fish sources this file for new interactive sessions.
        commonSecrets.enableCredentials = true;
        profile = "home";
      };
      vault = enabled;
    };
  };

  home = {
    file."Pictures/screenshots/.keep".text = "";
    packages = with pkgs; [
      iina
      neovim
    ];
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

  # Override Determinate's flaky install.determinate.systems substituter and
  # flakehub-weekly nix-path. See modules/home/tools/nix.
  custom.tools.nix = enabled;

  # ======================== DO NOT CHANGE THIS ========================
  home.stateVersion = "26.05";
  # ======================== DO NOT CHANGE THIS ========================
}
