let
  skill = import ../../shared/workflow/skill/architecture-review.nix;
in
{
  inherit (skill) description;
  task = skill.content;
}
