# Single source of truth for AI harness permissions.
#
# Shared vocabulary first — commands both harnesses gate the same way — then
# each provider assembles its own dialect from it (claude: allow/ask/deny
# string lists; opencode: flat glob→decision map). Per-provider deltas are
# named extras below, kept deliberately visible: they are historical drift,
# preserved for now; converging opencode to claude's stricter set is a
# planned follow-up, not a silent side effect of editing this file.
#
# Claude ask rules prompt in EVERY permission mode, including
# --dangerously-skip-permissions, so the claude ask list holds only actions
# worth a yes/no in a full-yolo run. Ask outranks allow (docs: "a matching
# ask rule prompts even when a more specific allow rule also matches"), so a
# catch-all allow with narrower ask rules carves prompts back out — that is
# how the git fork surface below works.
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
  # Git: everything allowed, fork work is the exception. `git push *` is
  # allowed wholesale; claudeGitForkAsk outranks it and prompts only for
  # pushing to a URL or wiring a fork remote. A push to a named fork remote
  # still passes silently — but `git remote add`/`set-url` prompted first,
  # so a fork enters the repo only through a human checkpoint.
  claudeGitAllow = [
    "git clone *"
    "git fetch *"
    "git add *"
    "git checkout *"
    "git commit *"
    "git merge *"
    "git pull *"
    "git push *"
    "git rebase *"
    "git reset *"
    "git restore *"
    "git stash *"
    "git switch *"
  ];
  claudeGitForkAsk = [
    "git remote add *"
    "git remote set-url *"
    "git push git@*"
    "git push ssh://*"
    "git push https://*"
    "git push http://*"
  ];
  claudeFileAllow = [
    "cp *"
    "mv *"
    "chmod *"
  ];
  # rm and curl stay gated even in yolo: irreversible deletion, and the one
  # plain-text exfil channel permission rules can usefully watch.
  claudeAsk = [
    "rm *"
    "curl *"
  ];
  # System switching is denied, not asked: deny blocks in every mode
  # (bypass included), so a yolo run cannot even prompt its way through.
  # AGENTS.md already forbids the agent from switching by hand.
  claudeMutationDeny = [
    "sudo *"
    "nixos-rebuild *"
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
      "Read(~/.ssh/config)"
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
    ]
    ++ bashify (claudeGitAllow ++ claudeFileAllow);
    ask = bashify (claudeGitForkAsk ++ claudeAsk);
    deny = bashify (destructiveDeny ++ envExposureDeny ++ claudeEnvDeny ++ claudeMutationDeny);
  };

  opencode = {
    edit = "allow";
    bash = {
      "*" = "allow";
    }
    // toPermissionMap "ask" (gitDangerousAsk ++ systemMutationAsk ++ opencodeAsk)
    // toPermissionMap "deny" (destructiveDeny ++ envExposureDeny);
    webfetch = "allow";
    external_directory = {
      "*" = "ask";
      "~/.ssh/config" = "allow";
    };
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
