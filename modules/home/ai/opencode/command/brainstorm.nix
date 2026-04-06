let
  workflow = import ../../shared/workflow/skill/brainstorm.nix;
in
{
  description = workflow.description;
  agent = "brainstorm-orchestrator";
  model = "hhdev-glm5-fp8/zai-org/GLM-5-FP8";

  requirements = ''
    Use the Forgejo-first brainstorming workflow in the current repository.
    Stay in chat until scope is good enough, then ask before creating or updating the issue.
    If the user is not ready to implement, leave an `AI-HANDOFF` comment and stop.
  '';

  task = ''
    Initial user context:
    $ARGUMENTS
  '';
}
