let
  workflow = import ../../shared/workflow/skill/complete.nix;
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
      "git branch --show-current" = "allow";
      "fj issue *" = "allow";
      "fj pr *" = "allow";
      "fj milestone *" = "allow";
      "git branch -d *" = "ask";
      "git push origin --delete *" = "ask";
    };
  };

  system_prompt = workflow.content;
}
