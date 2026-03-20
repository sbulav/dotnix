let
  workflow = import ../../shared/workflow/skill/resume.nix;
in
{
  description = workflow.description;
  mode = "subagent";
  model = "litellm/glm-5-fp8";
  temperature = 0.1;

  tools = {
    read = true;
    write = false;
    edit = false;
    grep = true;
    glob = true;
    bash = true;
  };

  permission = {
    edit = "deny";
    write = "deny";
    webfetch = "deny";
    bash = {
      "*" = "ask";
      "git status" = "allow";
      "git branch --show-current" = "allow";
      "git remote *" = "allow";
      "tea issues *" = "allow";
      "tea pulls *" = "allow";
      "jira issue view *" = "allow";
    };
  };

  system_prompt = workflow.content;
}
