let
  workflow = import ../../shared/workflow/skill/resume.nix;
in
{
  description = workflow.description;
  agent = "resume-orchestrator";
  model = "litellm/glm-5-fp8";

  requirements = ''
    Resume work from a Forgejo issue in the current repo.
    Prefer an explicit issue number. If ambiguous, ask instead of guessing.
  '';

  task = ''
    Resume target:
    $ARGUMENTS
  '';
}
