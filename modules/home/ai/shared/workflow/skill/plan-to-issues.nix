{
  name = "plan-to-issues";
  version = "1.0.0";
  description = "Break a planned Forgejo issue into vertical-slice sub-issues. Use with a parent issue number.";
  "argument-hint" = "[parent-issue-number]";
  "disable-model-invocation" = true;
  allowed-tools = [
    "Read"
    "Grep"
    "Glob"
    "Bash"
    "Task"
  ];
  content = ''
    Break a planned Forgejo issue into vertical-slice sub-issues using only the current repo.

     Hard rules:
     - Read the parent issue body and latest AI-HANDOFF first.
     - Explore the codebase to validate the plan against existing code.
     - Each slice must be a vertical slice (thin cross-layer feature), not a horizontal layer.
     - Propose all slices at once before creating any.
     - Each slice needs: goal, in-scope, acceptance criteria, dependencies, parent reference.
     - Ask one confirmation before creating all sub-issues.
     - Never create issues without user confirmation.
     - Use `tea` for issue creation.
     - Use `tea comment -R <forgejo-remote> <issue-number> $'...'` for handoff comments.
     - Never use `tea issue comment`, `tea api`, or `python3` for normal Forgejo workflow.
     - If runtime mode or permissions block writes, do not probe tokens, `curl`, config files, or API auth. State that posting is blocked and return the exact bodies for the user to post manually.
     - For `tea comment`, prefer a single safely quoted argument such as `$'...'`; avoid heredocs, command substitution, or backgrounded comment commands.
     - Never include system reminders, tool diagnostics, or internal policy text inside the handoff body.

    Workflow:
    1. Resolve parent issue from `$ARGUMENTS` or current branch.
    2. Fetch parent issue with `tea issues -R <forgejo-remote> <issue-number>`.
    3. Fetch comments with `tea issues -R <forgejo-remote> --comments -o json <issue-number>`.
    4. Extract the latest AI-HANDOFF and read the parent issue body.
    5. Explore the codebase to find existing patterns, validate assumptions, and identify integration points.
    6. Propose vertical slices. Each slice should be:
       - Small enough to implement in one focused session
       - Cross-layer (touches API/logic/storage, not just one layer)
       - Has its own acceptance criteria
       - Notes dependencies on other slices
    7. Present all slices to the user in a numbered list with:
       - Slice title
       - Goal (1 sentence)
       - What's in scope
       - Acceptance criteria
       - Dependencies on other slices (if any)
    8. Ask one confirmation: "Create all N sub-issues? (y/n)"
    9. Create sub-issues with title format: `#<parent> slice: <title>`
    10. Post AI-HANDOFF on parent issue with status `planned`, listing all created sub-issue numbers.

    Sub-issue body shape:
    - `## Цель`
    - `## Входит в scope`
    - `## Критерии готовности`
    - `## Зависимости`
    - `## Родительский issue`
       `#<parent-number>`

    Input:
    $ARGUMENTS
  '';
}
