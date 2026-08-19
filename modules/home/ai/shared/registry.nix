# Central AI registry — the single source both harness modules (claude,
# opencode) render from. Deliberately NOT named default.nix: Snowfall
# auto-discovers modules/**/default.nix as home modules, and this is a plain
# library, imported explicitly with `import ../shared/registry.nix { inherit lib; }`.
{ lib }:
let
  mcpCatalog = import ./mcp-servers.nix;

  optionalYamlField =
    key: value: if value != null && value != "" then "${key}: ${builtins.toJSON value}" else "";

  processSkillDir =
    dir:
    let
      files = builtins.readDir dir;
      nixFiles = lib.filterAttrs (name: _: lib.hasSuffix ".nix" name) files;
    in
    lib.mapAttrs' (
      name: _:
      let
        fileName = lib.removeSuffix ".nix" name;
        skill = import (dir + "/${name}");
      in
      lib.nameValuePair fileName skill
    ) nixFiles;

  forProvider = p: lib.filterAttrs (_: s: lib.elem p s.providers) mcpCatalog;
in
{
  # All shared skills — both harnesses emit every one of these.
  # shared/workflow/skill stays a separate directory because the opencode
  # orchestrator agents and commands import those files directly.
  skills = (processSkillDir ./skill) // (processSkillDir ./workflow/skill);

  # Claude Code and opencode consume the identical SKILL.md format.
  toSkillMarkdown = _name: skill: ''
    ---
    name: ${builtins.toJSON skill.name}
    description: ${builtins.toJSON skill.description}
    ${optionalYamlField "version" (skill.version or null)}
    ${optionalYamlField "argument-hint" (skill."argument-hint" or null)}
    ${optionalYamlField "disable-model-invocation" (skill."disable-model-invocation" or null)}
    ${optionalYamlField "user-invocable" (skill."user-invocable" or null)}
    ${optionalYamlField "model" (skill.model or null)}
    ${optionalYamlField "context" (skill.context or null)}
    ${optionalYamlField "agent" (skill.agent or null)}
    ${
      if (skill ? allowed-tools && skill.allowed-tools != [ ]) then
        "allowed-tools:\n" + lib.concatStringsSep "\n" (map (tool: "  - ${tool}") skill.allowed-tools)
      else
        ""
    }
    ---
    ${skill.content or ""}
  '';

  permissions = import ./permissions.nix;
  securityPatterns = import ./security-patterns.nix;

  # Per-harness MCP config shapes rendered from the one catalog.
  mcp = {
    claude = lib.mapAttrs (
      _: s:
      if s ? remote then
        {
          type = "http";
          url = s.remote.url;
        }
      else
        { inherit (s.local) command args; }
    ) (forProvider "claude");

    opencode = lib.mapAttrs (
      _: s:
      if s ? remote then
        {
          type = "remote";
          url = s.remote.url;
          enabled = s.enabled or true;
        }
      else
        {
          type = "local";
          command = [ s.local.command ] ++ s.local.args;
          enabled = s.enabled or true;
        }
    ) (forProvider "opencode");
  };
}
