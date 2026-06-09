let
  workflow = import ../../shared/workflow/skill/complete.nix;
in
{
  description = workflow.description;
  agent = "complete-orchestrator";

  requirements = ''
    Complete the issue workflow after merge in the current repo.
    Only close milestones when no open issues remain and the user agrees.
  '';

  task = ''
    Extra context:
    $ARGUMENTS
  '';
}
