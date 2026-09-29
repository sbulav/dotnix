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
  skillFiles = concatMap (name: [
    {
      name = ".agents/skills/${name}/SKILL.md";
      value.text = registry.toCodexSkillMarkdown name registry.skills.${name};
    }
    {
      name = ".agents/skills/${name}/agents/openai.yaml";
      value.text = registry.toCodexSkillPolicy name registry.skills.${name};
    }
  ]) cfg.skills;
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

    # One-time migration of hand-installed files. Preserve them before HM's
    # collision check; subsequent generations already point into the store.
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
