let
  skill = import ../../shared/skill/prototype.nix;
in
{
  inherit (skill) description;
  task = skill.content;
}
