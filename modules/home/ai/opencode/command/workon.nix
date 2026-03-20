let
  workflow = import ../../shared/workflow/skill/workon.nix;
in
{
  description = workflow.description;
  agent = "workon-orchestrator";
  model = "litellm/glm-5-fp8";

  requirements = ''
    Resume and work on a Forgejo issue in the current repo.
    Read issue state first, then implement according to acceptance criteria.
    Prefer an explicit issue number. If ambiguous, ask instead of guessing.
  '';

  task = ''
    Work target:
    $ARGUMENTS
  '';
}
