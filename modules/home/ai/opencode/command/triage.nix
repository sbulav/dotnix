let
  skill = import ../../shared/workflow/skill/triage.nix;
in
{
  inherit (skill) description;
  task = skill.content;
}
