let
  tea = (import ../templates.nix).teaConventions;
in
{
  name = "ship";
  version = "1.2.0";
  description = "Prepare commit and PR for the current issue branch. Posts handoff before commit and PR approval gates.";
  "disable-model-invocation" = true;
  allowed-tools = [
    "Read"
    "Grep"
    "Glob"
    "Bash"
    "Task"
    "Skill"
  ];
  content = ''
    Work from the current repo and current issue branch only.

    Goal: prepare a commit and a Forgejo PR without performing either one until the user approves.

     Hard rules:
     - Extract the Forgejo issue number from the current branch or ask the user.
     - Post `AI-HANDOFF` before asking for commit approval.
     - Post `AI-HANDOFF` before asking for PR approval.
     - Ask before `git commit`.
     - Ask before `tea pulls create`.
     - Push only when the user asks for it.

    ${tea}

     Steps:
     1. Inspect branch, working tree, staged changes, and unpushed commits.
     2. Load the Forgejo issue for the current repo only.
     3. Promotion gate — read the issue's latest `AI-HANDOFF` **Decision log** and test each entry against the `domain-modeling` bar: hard to reverse, surprising, and a real trade-off (a rejection with a load-bearing reason also counts). For any survivor, invoke the `domain-modeling` skill to write it into AGENTS.md so it lands in this same commit. Most handoffs promote nothing — skip silently.
     4. Draft a commit message with `Refs #<issue>` in the footer if appropriate.
     5. Post a handoff with status `ready-for-commit` using `tea comment`.
     6. Ask whether to commit.
     7. If committed, draft the PR:
        - title: `#<issue> <TPL-if-any> <human title>`
        - body includes `Closes #<issue>`
     8. Post a handoff with status `ready-for-pr` using `tea comment`.
     9. Ask whether to create the PR.
     10. If PR is created, post a handoff with status `pr-open` including the PR URL.

    Use the current repo only.
  '';
}
