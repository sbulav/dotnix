# Verified against official docs and hhdev inventories on 2026-11-13.
# Catalog entries are not proof of access; probe a new ID before routing to it.
let
  openai = {
    "gpt-6-astra" = {
      name = "GPT-6 Astra";
    };
    "gpt-6-sol" = {
      name = "GPT-6 Sol";
    };
    "gpt-6.1-sol" = {
      name = "GPT-6.1 Sol";
    };
    "gpt-6.1-terra" = {
      name = "GPT-6.1 Terra";
    };
    "gpt-6-luna" = {
      name = "GPT-6 Luna";
    };
  };
  anthropic = {
    "claude-haiku-5-5" = {
      name = "Claude Haiku 5.5";
    };
    "claude-sonnet-5-5" = {
      name = "Claude Sonnet 5.5";
    };
    "claude-opus-5-5" = {
      name = "Claude Opus 5.5";
    };
    "claude-fable-5-2" = {
      name = "Claude Fable 5.2";
    };
  };
in
{
  inherit openai anthropic;
  # Claude Code aliases track the provider's supported release. Full IDs in
  # the relay let callers choose explicitly; Sonnet 5.5 needs CLI >= 2.1.284.
  claudeAliases =
    map
      (id: {
        inherit id;
        displayName = id;
      })
      [
        "opus"
        "sonnet"
        "haiku"
        "fable"
        "opusplan"
      ]
    ++ map (id: {
      inherit id;
      displayName = anthropic.${id}.name;
    }) (builtins.attrNames anthropic);
}
