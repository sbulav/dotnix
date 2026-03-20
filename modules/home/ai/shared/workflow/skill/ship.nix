{
  name = "ship";
  version = "1.0.0";
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
     - Never push automatically.
     - Use `tea comment <issue-number> -R origin <body>` for handoff comments.
     - Never use `tea issue comment`, `tea api`, or `python3` for normal Forgejo workflow.

     Steps:
     1. Inspect branch, working tree, staged changes, and unpushed commits.
     2. Load the Forgejo issue for the current repo only.
     3. Draft a commit message with `Refs #<issue>` in the footer if appropriate.
     4. Post a handoff with status `ready-for-commit` using `tea comment`.
        - Include both `<!-- AI-HANDOFF -->` and a visible `**AI-HANDOFF**` heading.
     5. Ask whether to commit.
     6. If committed, draft the PR:
        - title: `#<issue> <TPL-if-any> <human title>`
        - body includes `Closes #<issue>`
     7. Post a handoff with status `ready-for-pr` using `tea comment`.
        - Include both `<!-- AI-HANDOFF -->` and a visible `**AI-HANDOFF**` heading.
     8. Ask whether to create the PR.
     9. If PR is created, post a handoff with status `pr-open` including the PR URL.

    Use the current repo only. Do not list or inspect issues from other repositories.
  '';
}
