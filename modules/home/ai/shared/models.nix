# Verified against official model docs on 2026-09-29. These are catalog
# entries, not proof of account/gateway access. Keep legacy fallbacks in providers.nix.
let
  openai = {
    "gpt-6-astra" = {
      name = "GPT-6 Astra";
    };
    "gpt-6-sol" = {
      name = "GPT-6 Sol";
    };
    "gpt-6-luna" = {
      name = "GPT-6 Luna";
    };
  };
  anthropic = {
    "claude-sonnet-5-5" = {
      name = "Claude Sonnet 5.5";
    };
    "claude-opus-5-5" = {
      name = "Claude Opus 5.5";
    };
    "claude-fable-5-1" = {
      name = "Claude Fable 5.1";
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
