let
  workflow = import ../../shared/workflow/skill/ship.nix;
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
    webfetch = "deny";
    bash = {
      "*" = "ask";
      "git status" = "allow";
      "git diff *" = "allow";
      "git log *" = "allow";
      "git branch --show-current" = "allow";
      "git remote *" = "allow";
      "git add *" = "ask";
      "git commit *" = "ask";
      "tea issues *" = "allow";
      "tea pulls *" = "allow";
      "tea comment *" = "allow";
      "tea pr create *" = "ask";
    };
  };

  system_prompt = workflow.content;
}
