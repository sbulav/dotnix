let
  workflow = import ../../shared/workflow/skill/ship.nix;
in
{
  inherit (workflow) description;
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
      "git diff *" = "allow";
      "git log *" = "allow";
      "git branch --show-current" = "allow";
      "git remote *" = "allow";
      "git add *" = "ask";
      "git commit *" = "ask";
      "fj issue *" = "allow";
      "fj pr *" = "allow";
    };
  };

  system_prompt = workflow.content;
}
