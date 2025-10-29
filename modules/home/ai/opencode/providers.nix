{
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
      "claude-sonnet-4-5-20250929" = {
        name = "Claude Sonnet 4.5 (2025-09-29)";
      };
      "claude-sonnet-4-20250514" = {
        name = "Claude Sonnet 4 (2025-05-14)";
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

  "hhdev-grok" = {
    name = "HHDev xAi Grok";
    npm = "@ai-sdk/xai";
    options = {
      apiKey = "{env:OPENAI_API_KEY}";
      baseURL = "https://llmgtw.hhdev.ru/proxy/xai";
    };
    models = {
      "grok-4-0709" = {name = "Grok 4";};
      "grok-code-fast-1" = {name = "Grok Code Fast 1";};
      "grok-4-fast-reasoning" = {name = "Grok 4 Fast Reasoning";};
    };
  };
}
