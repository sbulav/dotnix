{
  description = "Draft (and optionally apply) a Conventional Commit for staged changes";
  agent = "committer";
  model = "hhdev-glm5-fp8/zai-org/GLM-5.1-FP8";

  context = ''
    Staged summary:
    !`git status --porcelain=v1`

    Staged diff:
    !`git diff --staged`
  '';

  task = ''
    - Propose ONE Conventional Commit message (subject + body + any footers).
    - Ask me to confirm before committing.
    - If I confirm, perform the commit with the exact message.
  '';
}
