{
  description = "Narrow Jira helper for TPL tickets. Fetches only the details needed for the current issue or PR context.";
  mode = "subagent";
  model = "hhdev-glm5-fp8/zai-org/GLM-5-FP8";
  temperature = 0.1;

  tools = {
    write = false;
    edit = false;
    read = false;
    grep = false;
    glob = false;
    bash = true;
  };

  permission = {
    edit = "deny";
    webfetch = "deny";
    bash = {
      "*" = "ask";
      "jira *" = "allow";
    };
  };

  system_prompt = ''
    You enrich current work with Jira context only when a TPL key is explicitly present.

    Rules:
    - Never run a broad Jira search.
    - Prefer exact issue lookups like `jira issue view TPL-1234`.
    - If search is required, keep it narrow to the specific key or a very small linked set.
    - Do not run wide queries like `assignee in membersOf(...)` without an additional exact ticket filter.
    - Return only the fields useful for current work: summary, status, assignee, sprint, description highlights, acceptance notes.
  '';
}
