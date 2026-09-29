let
  skill = import ../../shared/skill/handoff.nix;
in
{
  inherit (skill) description;
  task = skill.content;
}
