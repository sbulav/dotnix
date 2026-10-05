{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.ai.codex;
  registry = import ../shared/registry.nix { inherit lib; };
  # Codex follows skill directory symlinks, but skips symlinked SKILL.md
  # files. Link each complete directory with regular files inside it.
  skillFiles = map (name: {
    name = ".agents/skills/${name}";
    value.source =
      pkgs.runCommand "codex-skill-${name}"
        {
          skillMarkdown = registry.toCodexSkillMarkdown name registry.skills.${name};
          skillPolicy = registry.toCodexSkillPolicy name registry.skills.${name};
          passAsFile = [
            "skillMarkdown"
            "skillPolicy"
          ];
        }
        ''
          mkdir -p "$out/agents"
          cp "$skillMarkdownPath" "$out/SKILL.md"
          cp "$skillPolicyPath" "$out/agents/openai.yaml"
        '';
  }) cfg.skills;
in
{
  options.custom.ai.codex = {
    enable = mkBoolOpt false "Whether to install shared skills for ChatGPT Work / Codex";
    skills = mkOpt (types.listOf (
      types.enum (builtins.attrNames registry.skills)
    )) (builtins.attrNames registry.skills) "Shared skills installed for the app and CLI";
  };

  config = mkIf cfg.enable {
    home.file = listToAttrs skillFiles;

    # Preserve existing directories (including the old per-file HM links and
    # any manual additions) before HM's collision check. Later generations
    # already link the whole directory into the store.
    # `run` honors HM dry-run mode. No backup or file mutation at build time.
    home.activation.backupManualCodexSkills = {
      before = [ "checkLinkTargets" ];
      after = [ ];
      data = ''
        backupRoot=${lib.escapeShellArg "${config.xdg.stateHome}/dotnix/codex-skills-backup"}/$(${pkgs.coreutils}/bin/date -u +%Y%m%dT%H%M%S)-$$
        for relative in ${lib.escapeShellArgs (map (f: f.name) skillFiles)}; do
          target="$HOME/$relative"
          if [ -e "$target" ] || [ -L "$target" ]; then
            if [ -L "$target" ]; then
              case "$(${pkgs.coreutils}/bin/readlink "$target")" in
                /nix/store/*) continue ;;
              esac
            fi
            run ${pkgs.coreutils}/bin/mkdir -p "$backupRoot/$(${pkgs.coreutils}/bin/dirname "$relative")"
            run ${pkgs.coreutils}/bin/mv -- "$target" "$backupRoot/$relative"
          fi
        done
      '';
    };
  };
}
