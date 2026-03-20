let
  workflow = import ../../shared/workflow/skill/workon.nix;
in
{
  description = workflow.description;
  mode = "subagent";
  model = "litellm/glm-5-fp8";
  temperature = 0.1;

  tools = {
    read = true;
    write = true;
    edit = true;
    grep = true;
    glob = true;
    bash = true;
  };

  permission = {
    webfetch = "deny";
    bash = {
      "*" = "ask";
      "git status" = "allow";
      "git diff *" = "allow";
      "git log *" = "allow";
      "git branch --show-current" = "allow";
      "git remote *" = "allow";
      "git add *" = "ask";
      "git checkout *" = "ask";
      "git commit *" = "deny";
      "git push *" = "deny";
      "git reset *" = "deny";
      "tea issues *" = "allow";
      "tea pulls *" = "allow";
      "tea comment *" = "allow";
      "jira issue view *" = "allow";
    };
  };

  system_prompt = workflow.content;
}
