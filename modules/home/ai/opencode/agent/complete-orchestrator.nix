let
  workflow = import ../../shared/workflow/skill/complete.nix;
in
{
  description = workflow.description;
  mode = "subagent";
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
      "*" = "allow";
      "git status" = "allow";
      "git branch --show-current" = "allow";
      "tea issues *" = "allow";
      "tea pulls *" = "allow";
      "tea milestones *" = "allow";
      "tea comment *" = "allow";
      "git branch -d *" = "ask";
      "git push origin --delete *" = "ask";
    };
  };

  system_prompt = workflow.content;
}
