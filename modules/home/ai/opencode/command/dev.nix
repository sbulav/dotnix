let
  skill = import ../../shared/workflow/skill/dev.nix;
in
{
  inherit (skill) description;
  task = skill.content;
}
