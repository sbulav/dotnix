let
  workflow = import ../../shared/workflow/skill/complete.nix;
in
{
  description = workflow.description;
  agent = "complete-orchestrator";
  model = "hhdev-glm5-fp8/zai-org/GLM-5-FP8";

  requirements = ''
    Complete the issue workflow after merge in the current repo.
    Only close milestones when no open issues remain and the user agrees.
  '';

  task = ''
    Extra context:
    $ARGUMENTS
  '';
}
