{
  lib,
  config,
  pkgs,
  namespace,
  ...
}: let
  inherit
    (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    mapAttrs'
    nameValuePair
    ;

  cfg = config.custom.ai.opencode;
in {
  options.custom.ai.opencode = {
    enable = mkEnableOption "Enable opencode AI assistent";
    settings = mkOption {
      type = types.attrs;
      default = {
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
      description = "Configuration for opencode.json";
    };
    agents = mkOption {
      type = types.attrsOf types.attrs;
      default = {};
      description = "Agent configuration files";
    };
    commands = mkOption {
      type = types.attrsOf types.attrs;
      default = {};
      description = "Command configuration files";
    };
    tools = mkOption {
      type = types.attrsOf types.lines;
      default = {};
      description = "Tool scripts placed in the tools directory";
    };
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      opencode
    ];
    xdg.configFile =
      {
        "opencode/opencode.json".text = builtins.toJSON cfg.settings;
      }
      // mapAttrs' (
        name: value:
          nameValuePair "opencode/agents/${name}.json" {text = builtins.toJSON value;}
      )
      cfg.agents
      // mapAttrs' (
        name: value:
          nameValuePair "opencode/commands/${name}.json" {text = builtins.toJSON value;}
      )
      cfg.commands
      // mapAttrs' (
        name: value:
          nameValuePair "opencode/tools/${name}" {
            text = value;
            executable = true;
          }
      )
      cfg.tools;
  };
}
