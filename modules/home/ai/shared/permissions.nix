# Single source of truth for AI harness permissions.
#
# Shared vocabulary first — commands both harnesses gate the same way — then
# each provider assembles its own dialect from it (claude: allow/ask/deny
# string lists; opencode: flat glob→decision map). Per-provider deltas are
# named extras below, kept deliberately visible: they are historical drift,
# preserved for now; converging opencode to claude's stricter set is a
# planned follow-up, not a silent side effect of editing this file.
let
  # --- shared vocabulary: gated identically in both harnesses ---
  destructiveDeny = [
    "rm -rf /*"
    "dd *"
    "mkfs *"
  ];
  # Environment dumps expose injected secrets
  envExposureDeny = [
    "env"
    "env *"
    "printenv"
    "printenv *"
    "set"
    "export -p"
  ];
  gitDangerousAsk = [
    "git push *"
    "git rebase *"
    "git reset *"
  ];
  systemMutationAsk = [
    "chmod *"
    "sudo *"
    "nixos-rebuild *"
    "rm *"
  ];

  # --- claude-only extras ---
  claudeGitAsk = [
    "git add *"
    "git checkout *"
    "git commit *"
    "git merge *"
    "git pull *"
    "git restore *"
    "git stash *"
    "git switch *"
  ];
  claudeFileAsk = [
    "cp *"
    "mv *"
    "curl *"
  ];
  claudeEnvDeny = [ "declare -p *" ];

  # --- opencode-only extras ---
  opencodeAsk = [ "chown *" ];

  bashify = map (c: "Bash(${c})");
  toPermissionMap =
    decision: cmds:
    builtins.listToAttrs (
      map (c: {
        name = c;
        value = decision;
      }) cmds
    );
in
{
  claude = {
    defaultMode = "auto";
    allow = [
      "Glob"
      "Grep"
      "Read"
      "Task"
      "TodoWrite"
      # Git — safe read-only ops
      "Bash(git status)"
      "Bash(git log *)"
      "Bash(git diff *)"
      "Bash(git show *)"
      "Bash(git branch *)"
      "Bash(git remote *)"
      # Forgejo via tea
      "Bash(tea issues *)"
      "Bash(tea pulls *)"
      "Bash(tea comment *)"
      "Bash(tea issues create *)"
      "Bash(tea pr create *)"
      # Basic filesystem
      "Bash(ls *)"
      "Bash(mkdir *)"
      # Nix tooling
      "Bash(nix *)"
      "Bash(nixos-option *)"
      "Bash(systemctl list-units *)"
      "Bash(systemctl list-timers *)"
      "Bash(systemctl status *)"
      "Bash(journalctl *)"
      "Bash(claude --version)"
      "WebFetch(domain:github.com)"
      "WebFetch(domain:raw.githubusercontent.com)"
    ];
    ask = bashify (claudeGitAsk ++ gitDangerousAsk ++ claudeFileAsk ++ systemMutationAsk);
    deny = bashify (destructiveDeny ++ envExposureDeny ++ claudeEnvDeny);
  };

  opencode = {
    edit = "allow";
    bash = {
      "*" = "allow";
    }
    // toPermissionMap "ask" (gitDangerousAsk ++ systemMutationAsk ++ opencodeAsk)
    // toPermissionMap "deny" (destructiveDeny ++ envExposureDeny);
    webfetch = "allow";
    external_directory = "ask";
  };

  # Reusable per-agent fragments for opencode agent definitions.
  opencodeAgents = {
    # Read-and-commit agents (committer, nix-expert): git allowed but the
    # history-rewriting and remote-touching ops gated or denied.
    gitCareful = {
      edit = "deny";
      webfetch = "deny";
      bash = {
        "*" = "allow";
        "git status" = "allow";
        "git diff *" = "allow";
        "git log *" = "allow";
        "git add *" = "ask";
        "git restore --staged *" = "allow";
        "git commit -m *" = "allow";
        "git commit --amend *" = "ask";
        "git tag -a * -m *" = "ask";
        "git push *" = "ask";
        "git rebase *" = "deny";
        "git reset *" = "deny";
        "rm -rf *" = "deny";
      };
    };
  };
}
