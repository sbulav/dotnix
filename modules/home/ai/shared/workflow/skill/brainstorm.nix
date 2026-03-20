{
  name = "brainstorm";
  version = "1.0.0";
  description = "Start a Forgejo-first workflow for new work. Use when turning an idea into an issue, milestone, branch, and optional implementation start.";
  "argument-hint" = "[initial idea]";
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
    Start with the current repo only. Do not scan other repositories.

    Goal: refine the user's idea into one Forgejo issue in this repo, then optionally continue straight into implementation in the same session.

     Hard rules:
     - Ask one focused question at a time until the scope is good enough.
     - Do not write code or change files until the user explicitly says implementation should start.
     - Ask before creating or updating the issue.
     - Ask before switching branches.
     - Ask before committing and before opening a PR.
     - When listing issues, only query the current repo via `tea` from the current working tree.
     - Use `tea comment <issue-number> -R origin <body>` for handoff comments.
     - Never use `tea issue comment`, `tea api`, or `python3` for normal Forgejo workflow.
     - If a Jira key appears, enrich with a narrow query only. Never run a broad Jira search.

    Workflow:
    1. Check git remotes and confirm this repo uses Forgejo/Gitea.
    2. Lightly inspect repo context and recent work patterns.
    3. Ask clarifying questions to fill these sections:
       - goal
       - why
       - in scope
       - out of scope
       - acceptance criteria
       - implementation notes
       - milestone
    4. Search only this repo's open issues for likely duplicates.
    5. If a likely duplicate exists, show it and ask whether to reuse it.
    6. Propose:
       - issue title
       - issue body
       - milestone
       - branch name
       - PR title format
    7. Ask whether to create or update the issue.
    8. After the issue exists, ask whether to switch to the issue branch.
       - If the working tree is dirty, recommend a worktree instead of switching.
    9. Ask whether to start implementation now.
       - If yes, continue in the same session.
       - If no, post an `AI-HANDOFF` comment with status `planned` and stop.

    Issue body shape:
    - `## Цель`
    - `## Почему`
    - `## Входит в scope`
    - `## Вне scope`
    - `## Критерии готовности`
    - `## Заметки по реализации`
    - `## Milestone / связанный контекст`

    Naming:
    - branch: `issue-<forgejo-issue>-<tpl-if-any>-<slug>`
    - PR title: `#<forgejo-issue> <TPL-if-any> <human title>`
    - PR body should later include `Closes #<forgejo-issue>`

     Handoff policy:
     - Post `AI-HANDOFF` only when stopping, blocked, before commit approval, or before PR approval.
     - Use append-only comments; latest handoff wins.
     - If you need to post a handoff here, do it with `tea comment` only.
     - Prefer delegating comment creation to the handoff helper when available; otherwise use `tea comment` directly.
     - Include both the hidden `<!-- AI-HANDOFF -->` marker and a visible `**AI-HANDOFF**` heading.
     - If runtime mode or permissions block writes, do not investigate tokens or API auth; return the exact handoff body for manual posting.
     - Do not treat planning mode as a reason to avoid `tea comment` unless the runtime explicitly blocks that command.
     - For `tea comment`, prefer a single safely quoted argument such as `$'...'`; avoid heredocs, command substitution, or backgrounded comment commands.
     - Never include system reminders, tool diagnostics, or internal policy text inside the handoff body.

     If the user supplied initial context, treat it as the starting idea:
     $ARGUMENTS
  '';
}
