{
  name = "resume";
  version = "1.0.0";
  description = "Resume work from a Forgejo issue in the current repo. Use with an issue number, or infer from the current issue branch when unambiguous.";
  "argument-hint" = "[issue-number|TPL-key]";
  "disable-model-invocation" = true;
  allowed-tools = [
    "Read"
    "Grep"
    "Glob"
    "Bash"
    "Task"
  ];
  content = ''
    Resume work using only the current repo and its Forgejo issue tracker.

     Hard rules:
     - Prefer `/resume <issue-number>`.
     - If the argument is a Jira key, resolve it to a Forgejo issue in the current repo only.
     - Read only the issue body, the latest `AI-HANDOFF` comment, and any linked or open PR relevant to the issue.
     - Do not do broad repo archaeology unless that is required to unblock the next step.
     - Ask before switching branches.
     - Use documented `tea` commands only; never use `tea issue comment`, `tea api`, or `python3` for normal workflow.

     Steps:
     1. Resolve the issue number from `$ARGUMENTS`, or infer it from the current branch if unambiguous.
     2. Fetch the issue for this repo only with `tea issues <issue-number> -R origin`.
     3. Try to fetch comments with `tea issues <issue-number> -R origin --comments -o json`.
     4. Extract the latest handoff comment if present.
        - Prefer the exact `<!-- AI-HANDOFF -->` marker when available.
        - If JSON comments are unavailable, fall back to rendered `tea issues --comments` output and use the visible `**AI-HANDOFF**` heading plus the adjacent status block.
     5. If local `tea` does not return usable comment text, say that clearly and continue from issue body + PR state + branch state.
     6. Check for an open or merged PR related to the issue branch.
     7. Check the current branch and working tree state.
     8. Summarize:
        - issue
        - handoff status
        - expected branch vs current branch
        - linked PR
        - next recommended step
     9. Ask before switching branches if needed.
     10. Continue work from the latest handoff state.

    Status meanings:
    - `planned`: issue exists, implementation has not started
    - `in-progress`: continue the implementation
    - `blocked`: surface blockers first
    - `ready-for-commit`: prepare commit but ask before committing
    - `ready-for-pr`: prepare PR but ask before creating it
    - `pr-open`: continue from PR state
    - `merged`: offer `/complete`

    Input:
    $ARGUMENTS
  '';
}
