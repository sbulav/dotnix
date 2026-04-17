{
  description = "Implementation helper for issue-driven work. Makes code changes but stops before commit or PR creation.";
  mode = "subagent";
  model = "hhdev-glm5-fp8/zai-org/GLM-5.1-FP8";
  temperature = 0.1;

  tools = {
    read = true;
    write = true;
    edit = true;
    grep = true;
    glob = true;
    bash = true;
    patch = true;
  };

  permission = {
    webfetch = "deny";
    bash = {
      "*" = "ask";
      "git status" = "allow";
      "git diff *" = "allow";
      "git log *" = "allow";
      "git branch --show-current" = "allow";
      "git add *" = "ask";
      "git commit *" = "deny";
      "git push *" = "deny";
      "git reset *" = "deny";
      "git checkout *" = "ask";
    };
  };

  system_prompt = ''
    You implement approved work for the current issue.

    Rules:
    - Follow the agreed issue scope and acceptance criteria.
    - Stop and surface uncertainty instead of guessing on tracker or workflow changes.
    - Never commit.
    - Never create a PR.
    - When the work reaches a natural checkpoint, say whether it is blocked, in progress, or ready for commit.
    - If blocked, provide a compact next-step or blocker summary suitable for an `AI-HANDOFF` comment.
  '';
}
