{
  "hhdev-openai" = {
    npm = "@ai-sdk/openai";
    name = "HHDev Gateway";
    options = {
      baseURL = "https://llmgtw.hhdev.ru/proxy/openai/";
      apiKey = "{env:OPENAI_API_KEY}";
    };
    models = {
      "gpt-5.5" = {
        name = "ChatGPT 5.5";
      };
      "gpt-5-mini" = {
        name = "ChatGPT 5 Mini";
        options = {
          reasoning = false;
        };
      };
      "gpt-4.1" = {
        name = "ChatGPT 4.1";
      };
      # "gpt-5.3-codex" = {
      #   name = "ChatGPT 5.3 Codex";
      # };
      # "gpt-5.3" = {
      #   name = "ChatGPT 5.3";
      # };
      # "gpt-5.4" = {
      #   name = "ChatGPT 5.4";
      # };
    };
  };

  "hhdev-anthropic" = {
    name = "HHDev Anthropic Gateway";
    npm = "@ai-sdk/anthropic";
    models = {
      "claude-sonnet-4-6" = {
        name = "Claude Sonnet 4.6";
      };
      "claude-opus-4-7" = {
        name = "Claude Opus 4.7";
      };
      "claude-opus-4-8" = {
        name = "Claude Opus 4.8";
      };
      "claude-fable-5" = {
        name = "Claude Fable 5";
      };
      "claude-haiku-4-5-20251001" = {
        name = "Claude Haiku 4.5 (2025-10-01)";
        options = {
          max_tokens = 8192;
        };
      };
    };
    options = {
      apiKey = "{env:OPENAI_API_KEY}";
      baseURL = "https://llmgtw.hhdev.ru/proxy/anthropic/v1";
      max_tokens = 8192;
      headers = {
        "anthropic-version" = "2023-06-01";
      };
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
      "gemini-3.1-pro-preview" = {
        name = "Gemini 3.1 Pro Preview";
      };
    };
  };

  "hhdev-grok" = {
    name = "HHDev xAi Grok";
    npm = "@ai-sdk/xai";
    options = {
      apiKey = "{env:OPENAI_API_KEY}";
      baseURL = "https://llmgtw.hhdev.ru/proxy/xai";
    };
    models = {
      "grok-4.5" = {
        id = "grok-4.5";
        name = "Grok 4.5";
        cost = {
          input = 0.2;
          output = 0.6;
          cache_read = 0.05;
          context_over_200k = {
            input = 0.4;
            output = 1.2;
            cache_read = 0.1;
          };
        };
        limit = {
          context = 500000;
          output = 60000;
        };
      };
    };
  };

  "hhdev-glm5-fp8" = {
    name = "GLM-5.2 FP8";
    npm = "@ai-sdk/openai-compatible";
    options = {
      baseURL = "https://llm-gateway.pyn.ru/proxy/glm5-fp8/v1";
      apiKey = "{env:OPENAI_API_PYN_KEY}";
    };
    models = {
      "zai-org/GLM-5.2-FP8" = {
        name = "GLM-5.2 FP8";
      };
      # limit = {
      #   context = 8000;
      #   output = 10000;
      # };
    };
  };

  # "pyn-gpt-oss-120b" = {
  #   name = "GPT-OSS 120B";
  #   npm = "@ai-sdk/openai-compatible";
  #   options = {
  #     baseURL = "https://llm-gateway.pyn.ru/proxy/gpt-oss-120b/v1";
  #     apiKey = "{env:OPENAI_API_KEY}";
  #   };
  #   models = {
  #     "gpt-oss-120b" = {
  #       name = "GPT-OSS 120B";
  #     };
  #   };
  # };

}
