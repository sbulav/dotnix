let
  workflow = import ../../shared/workflow/skill/plan-to-issues.nix;
in
{
  description = workflow.description;
  agent = "plan-to-issues-orchestrator";
  model = "hhdev-glm5-fp8/zai-org/GLM-5.1-FP8";

  requirements = ''
    Break a planned Forgejo issue into vertical-slice sub-issues.
    Read the parent issue first, explore the codebase, then propose slices.
    Ask for confirmation before creating any issues.
  '';

  task = ''
    Parent issue:
    $ARGUMENTS
  '';
}
