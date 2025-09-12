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

    desktop = {
      hyprland = enabled;
      addons = {
        hyprpaper = enabled;
        mako = enabled;
        rofi = enabled;
        kitty = disabled;
        swaylock = enabled;
        hypridle = enabled;
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

    ai = {
      opencode = {
        enable = true;
        # Contents written to ~/.config/opencode/opencode.json
        settings = {
          model = "hhdev-openai/gpt-4.1";
          small_model = "hhdev-openai/gpt-4.1";

          disabled_providers = [
            "openai"
            "amazon-bedrock"
            "opencode"
          ];

          provider = {
            "hhdev-openai" = {
              npm = "@ai-sdk/openai-compatible";
              name = "HHDev Gateway";
              options = {
                baseURL = "https://llmgtw.hhdev.ru/proxy/openai/";
                apiKey = "{env:OPENAI_API_KEY}";
              };
              models = {
                "gpt-5" = {name = "ChatGPT 5";};
                "gpt-5-mini" = {
                  name = "ChatGPT 5 Mini";
                  options = {reasoning = false;};
                };
                "gpt-4.1" = {name = "ChatGPT 4.1";};
              };
            };

            "hhdev-anthropic" = {
              name = "HHDev Anthropic Gateway";
              npm = "@ai-sdk/anthropic";
              models = {
                "claude-sonnet-4-20250514" = {
                  name = "Claude Sonnet 4 (2025-05-14)";
                };
                "claude-3-5-haiku-20241022" = {
                  name = "Claude Haiku 3.5 (2024-10-22)";
                };
              };
              options = {
                apiKey = "{env:OPENAI_API_KEY}";
                baseURL = "https://llmgtw.hhdev.ru/proxy/anthropic/v1";
                headers = {"anthropic-version" = "2023-06-01";};
              };
            };

            "hhdev-deepseek" = {
              name = "HHDev DeepSeek Gateway";
              npm = "@ai-sdk/openai-compatible";
              models = {
                "deepseek-chat" = {
                  name = "DeepSeek Chat";
                  options = {
                    max_tokens = 2048;
                    temperature = 0.3;
                  };
                };
                "deepseek-coder" = {
                  name = "DeepSeek Coder";
                  options = {
                    max_tokens = 4096;
                    temperature = 0.3;
                  };
                };
              };
              options = {
                apiKey = "{env:OPENAI_API_KEY}";
                baseURL = "https://llmgtw.hhdev.ru/proxy/deepseek";
                max_tokens = 2048;
              };
            };

            "hhdev-google" = {
              name = "HHDev Google Gateway";
              npm = "@ai-sdk/google";
              options = {
                apiKey = "{env:OPENAI_API_KEY}";
                baseURL = "https://llmgtw.hhdev.ru/proxy/google/v1beta";
              };
              models = {
                "gemini-2.5-pro" = {
                  name = "Gemini 2.5 Pro";
                  options = {
                    max_tokens = 65536;
                    temperature = 1;
                    top_p = 0.95;
                    top_k = 64;
                  };
                };
                "gemini-1.5-pro" = {
                  name = "Gemini 1.5 Pro";
                  options = {
                    max_tokens = 8192;
                    temperature = 1;
                    top_p = 0.95;
                    top_k = 40;
                  };
                };
              };
            };
          };

          "$schema" = "https://opencode.ai/config.json";
        };
      };
      # Optional: define custom agents, commands, or tools
      # agents."my-agent" = {
      #   provider = "anthropic";
      #   model    = "claude-3.5-sonnet";
      #   prompt   = "You are a concise coding assistant.";
      # };
    };

    apps = {
      obsidian = enabled;
      ktalk = enabled;
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
      direnv = disabled;
      gh = enabled;
      git = enabled;
      k9s = enabled;
      opentofu = enabled;
      yandex-cloud = enabled;
    };
    security = {
      rbw = enabled;
      vault = enabled;
      openconnect = enabled;
      sops = {
        enable = true;
        # Shared module auto-resolves to secrets/sab/default.yaml
        commonSecrets.enableCredentials = true;
        profile = "home";
      };
    };
  };

  # env_credentials now handled by commonSecrets.enableCredentials = true
  home.stateVersion = "23.11";
}
