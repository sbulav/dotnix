let
  workflow = import ../../shared/workflow/skill/ship.nix;
in
{
  description = workflow.description;
  agent = "ship-orchestrator";
  model = "hhdev-glm5-fp8/zai-org/GLM-5-FP8";

  requirements = ''
    Prepare commit and PR for the current issue branch.
    Ask before commit and ask before PR creation.
  '';

  task = ''
    Extra context:
    $ARGUMENTS
  '';
}
