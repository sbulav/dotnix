let
  models = import ../shared/models.nix;
in
{
  # The built-in provider retains its auth and Responses transport. Explicit
  # catalog entries also work before the bundled models.dev list catches up.
  openai.models = models.openai;

  "hhdev-openai" = {
    canonical = "openai";
    package = "@opencode/ai/providers/openai/responses";
    name = "HHDev Gateway";
    settings = {
      baseURL = "https://llmgtw.hhdev.ru/proxy/openai/";
      apiKey = "{env:OPENAI_API_KEY}";
      transport = "http";
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
    }
    // models.openai;
  };

  "hhdev-anthropic" = {
    name = "HHDev Anthropic Gateway";
    canonical = "anthropic";
    package = "@opencode/ai/providers/anthropic";
    # hhdev rejects thinking.adaptive.block_binding even for current Claude
    # models. This override is model-only and leaves direct Anthropic intact.
    models =
      builtins.mapAttrs
        (
          _: model:
          model
          // {
            compatibility.supportsThinkingBlockBinding = false;
          }
        )
        (
          {
            "claude-opus-4-8" = {
              name = "Claude Opus 4.8";
            };
            "claude-opus-5" = {
              name = "Claude Opus 5";
            };
          }
          // models.anthropic
        );
    settings = {
      apiKey = "{env:OPENAI_API_KEY}";
      baseURL = "https://llmgtw.hhdev.ru/proxy/anthropic/v1";
    };
    headers = {
      "anthropic-version" = "2023-06-01";
    };
  };

  # The gateway's deepseek-flash alias now advertises V4.1 Flash. Keep the
  # old request budgets until larger outputs and tool round trips are verified;
  # the self-hosted hhdev-deepseek-v4-flash remains the routed backup.
  "hhdev-deepseek" = {
    name = "HHDev DeepSeek Gateway";
    canonical = "deepseek";
    package = "@opencode/ai/providers/openai-compatible";
    models = {
      "deepseek-flash" = {
        name = "DeepSeek V4.1 Flash";
        body = {
          max_tokens = 2048;
          temperature = 0.3;
        };
      };
      "deepseek-v4-pro" = {
        name = "DeepSeek V4 Pro";
        body = {
          max_tokens = 4096;
          temperature = 0.3;
        };
      };
    };
    settings = {
      apiKey = "{env:OPENAI_API_KEY}";
      baseURL = "https://llmgtw.hhdev.ru/proxy/deepseek";
    };
  };

  "hhdev-google" = {
    name = "HHDev Google Gateway";
    canonical = "google";
    package = "@opencode/ai/providers/google";
    settings = {
      apiKey = "{env:OPENAI_API_KEY}";
      baseURL = "https://llmgtw.hhdev.ru/proxy/google/v1beta";
    };
    models = {
      "gemini-3.8-flash" = {
        name = "Gemini 3.8 Flash";
      };
      "gemini-4-argon" = {
        name = "Gemini 4 Argon";
        # The gateway advertises a lower output ceiling than Google's public
        # synchronous limit. Keep the deployment's conservative budget.
        limit = {
          context = 1048576;
          output = 32768;
        };
      };
    };
  };

  "hhdev-grok" = {
    name = "HHDev xAi Grok";
    canonical = "xai";
    package = "@opencode/ai/providers/xai";
    settings = {
      apiKey = "{env:OPENAI_API_KEY}";
      baseURL = "https://llmgtw.hhdev.ru/proxy/xai";
    };
    models = {
      "grok-4.7" = {
        name = "Grok 4.7";
        # Public xAI rates; no hhdev-specific discount has been verified.
        cost = [
          {
            input = 2;
            output = 6;
            cache.read = 0.5;
          }
          {
            tier = {
              type = "context";
              size = 200000;
            };
            input = 4;
            output = 12;
            cache.read = 1;
          }
        ];
        limit = {
          context = 500000;
          output = 60000;
        };
      };
    };
  };

  # GLM-5.3 Flash is deployed under the old glm5-fp8 endpoint name — the URL
  # does not match the model. Deployment limits checked on 2026-11-03.
  "hhdev-glm5-fp8" = {
    name = "GLM-5.3 Flash";
    package = "@opencode/ai/providers/openai-compatible";
    settings = {
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
        capabilities = {
          tools = true;
          input = [ "text" ];
          output = [ "text" ];
          reasoning.supported = true;
        };
        compatibility = {
          reasoningField = "reasoning_content";
          maxTokensField = "max_tokens";
        };
        limit = {
          context = 262144;
          output = 32768;
        };
        cost = {
          input = 0;
          output = 0;
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
    package = "@opencode/ai/providers/openai-compatible";
    settings = {
      baseURL = "https://llm-gateway.pyn.ru/proxy/gemma-4-26b-a4b-it/v1";
      apiKey = "{env:OPENAI_API_PYN_KEY}";
    };
    models = {
      "google/gemma-4-26B-A4B-it" = {
        name = "Gemma 4 26B A4B";
        capabilities = {
          tools = true;
          input = [
            "text"
            "image"
          ];
          output = [ "text" ];
          reasoning.supported = true;
        };
        compatibility = {
          reasoningField = "reasoning_content";
          maxTokensField = "max_tokens";
        };
        body = {
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
    package = "@opencode/ai/providers/openai-compatible";
    settings = {
      baseURL = "https://llm-gateway.pyn.ru/proxy/deepseek-v4-flash-0731/v1";
      apiKey = "{env:OPENAI_API_PYN_KEY}";
    };
    models = {
      "deepseek-ai/DeepSeek-V4-Flash-0731" = {
        name = "HHDev DeepSeek V4 Flash";
        capabilities = {
          tools = true;
          input = [ "text" ];
          output = [ "text" ];
          reasoning.supported = true;
        };
        compatibility = {
          reasoningField = "reasoning_content";
          maxTokensField = "max_tokens";
        };
        body = {
          chat_template_kwargs = {
            thinking = true;
          };
        };
        limit = {
          context = 131072;
          output = 32000;
        };
        cost = {
          input = 0;
          output = 0;
        };
      };
    };
  };
}
