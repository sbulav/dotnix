{
  "hhdev-openai" = {
    npm = "@ai-sdk/openai";
    name = "HHDev Gateway";
    options = {
      baseURL = "https://llmgtw.hhdev.ru/proxy/openai/";
      apiKey = "{env:OPENAI_API_KEY}";
    };
    models = {
      "gpt-5" = {
        name = "ChatGPT 5";
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
      "gpt-5.2-codex" = {
        name = "ChatGPT 5.2 Codex";
      };
      "gpt-5.2" = {
        name = "ChatGPT 5.2";
      };
    };
  };

  "hhdev-anthropic" = {
    name = "HHDev Anthropic Gateway";
    npm = "@ai-sdk/anthropic";
    models = {
      "claude-sonnet-4-5-20250929" = {
        name = "Claude Sonnet 4.5 (2025-09-29)";
      };
      "claude-opus-4-6" = {
        name = "Claude Opus 4.6";
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
      "grok-4-1-fast-reasoning" = {
        name = "Grok 4.1 Fast Reasoning";
      };
    };
  };

  "litellm" = {
    name = "HH";
    npm = "@ai-sdk/openai-compatible";
    options = {
      baseURL = "http://gpu1.pyn.ru:40000/v1";
      apiKey = "sk-any";
    };
    models = {
      "glm-5-fp8" = {
        name = "GLM-5 FP8";
      };
      "minimax-m2.5" = {
        name = "MiniMax M2.5";
      };
      "gpt-oss-120b" = {
        name = "GPT-OSS 120B";
      };
    };
  };
}
