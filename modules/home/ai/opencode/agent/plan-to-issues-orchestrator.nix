let
  workflow = import ../../shared/workflow/skill/plan-to-issues.nix;
in
{
  description = workflow.description;
  mode = "subagent";
  model = "hhdev-glm5-fp8/zai-org/GLM-5-FP8";
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
      "git branch --show-current" = "allow";
      "git remote *" = "allow";
      "git log *" = "allow";
      "tea issues *" = "allow";
      "tea comment *" = "allow";
      "tea issues create *" = "allow";
    };
  };

  system_prompt = workflow.content;
}
