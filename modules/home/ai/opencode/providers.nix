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
      "gpt-5.6-sol" = {
        name = "ChatGPT 5.6 Sol";
      };
      "gpt-5.6-terra" = {
        name = "ChatGPT 5.6 Terra";
      };
      "gpt-5.6-luna" = {
        name = "ChatGPT 5.6 Luna";
      };
    };
  };

  "hhdev-anthropic" = {
    name = "HHDev Anthropic Gateway";
    npm = "@ai-sdk/anthropic";
    models = {
      "claude-opus-4-8" = {
        name = "Claude Opus 4.8";
      };
      "claude-fable-5-1" = {
        name = "Claude Fable 5.1";
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

  # Legacy gateway DeepSeek. Kept configured but not routed: max_tokens is
  # capped at 2048/4096, too small for real subtasks. The self-hosted
  # hhdev-deepseek-v4-flash below is the usable DeepSeek lane.
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
      "grok-4.6" = {
        id = "grok-4.6";
        name = "Grok 4.6";
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

  # GLM-5.3 Flash is deployed under the old glm5-fp8 endpoint name — the URL
  # does not match the model. Brand-new release; speed/bug feedback pending.
  "hhdev-glm5-fp8" = {
    name = "GLM-5.3 Flash";
    npm = "@ai-sdk/openai-compatible";
    options = {
      baseURL = "https://llm-gateway.pyn.ru/proxy/glm5-fp8/v1";
      apiKey = "{env:OPENAI_API_PYN_KEY}";
    };
    models = {
      "zai-org/GLM-5.3-Flash" = {
        name = "GLM-5.3 Flash";
        # Thinks by default — emits reasoning_content even without kwargs.
        # Give it max_tokens headroom or the budget is spent on thinking and
        # content comes back empty. Thinking can be switched off per request
        # via chat_template_kwargs.enable_thinking = false.
        reasoning = true;
        limit = {
          context = 131072;
          output = 32768;
        };
      };
    };
  };

  # Self-hosted on the pyn.ru gateway (same box family as GLM-5.3 Flash): free, fast,
  # 128k context. Reasoning is OFF unless the request explicitly carries
  # chat_template_kwargs.enable_thinking — vLLM's chat template gates it there,
  # not behind a `reasoning` flag.
  "hhdev-gemma4-26b" = {
    name = "Gemma 4 26B A4B it";
    npm = "@ai-sdk/openai-compatible";
    options = {
      baseURL = "https://llm-gateway.pyn.ru/proxy/gemma-4-26b-a4b-it/v1";
      apiKey = "{env:OPENAI_API_PYN_KEY}";
    };
    models = {
      "google/gemma-4-26B-A4B-it" = {
        name = "Gemma 4 26B A4B";
        options = {
          chat_template_kwargs = {
            enable_thinking = true;
          };
        };
        limit = {
          context = 128000;
          output = 16000;
        };
        cost = {
          input = 0;
          output = 0;
        };
      };
    };
  };

  # Self-hosted DeepSeek-V4-Flash on pyn.ru gateway. Reasoning requires
  # chat_template_kwargs.thinking = true (not enable_thinking).
  "hhdev-deepseek-v4-flash" = {
    name = "HHDev DeepSeek V4 Flash";
    npm = "@ai-sdk/openai-compatible";
    options = {
      baseURL = "https://llm-gateway.pyn.ru/proxy/deepseek-v4-flash-0731/v1";
      apiKey = "{env:OPENAI_API_PYN_KEY}";
    };
    models = {
      "deepseek-ai/DeepSeek-V4-Flash-0731" = {
        name = "HHDev DeepSeek V4 Flash";
        reasoning = true;
        options = {
          chat_template_kwargs = {
            thinking = true;
          };
        };
        cost = {
          input = 0;
          output = 0;
        };
      };
    };
  };
}
