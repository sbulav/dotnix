let
  tea = (import ../templates.nix).teaConventions;
in
{
  name = "workon";
  version = "1.4.0";
  description = "Resume and work on a Forgejo issue — read state, then implement. Use with an issue number, or infer from the current issue branch when unambiguous.";
  "argument-hint" = "[issue-number|TPL-key]";
  "disable-model-invocation" = true;
  allowed-tools = [
    "Read"
    "Grep"
    "Glob"
    "Bash"
    "Task"
    "Write"
    "Edit"
    "Skill"
  ];
  content = ''
    Resume and implement work using only the current repo and its Forgejo issue tracker.

     Hard rules:
     - Prefer `/workon <issue-number>`.
     - If the argument is a Jira key, resolve it to a Forgejo issue in the current repo only.
     - Read only the issue body, the latest `AI-HANDOFF` comment, and any linked or open PR relevant to the issue.
     - Do broad repo archaeology only when it is required to unblock the next step.
     - Use the assigned branch/worktree. Ask before switching the user's working tree only when that switch has not already been authorized.
     - Follow issue scope and acceptance criteria strictly.
     - Stop at natural checkpoints and report status via AI-HANDOFF.
     - Leave commits and PRs to `/ship` — suggest it when ready.
     - In a delegated worker session, return the handoff to the parent; post it
       only when posting was explicitly assigned. The parent owns integration
       and shipping. A short handoff does not need its own helper session.
     - Planning mode alone is no reason to avoid `tea comment` — skip it only when the runtime explicitly blocks that command.

    ${tea}

     Steps:
     1. Resolve the issue number from `$ARGUMENTS`, or infer it from the current branch if unambiguous.
     2. Fetch the issue for this repo only with `tea issues -R <forgejo-remote> <issue-number>`.
     3. Try to fetch comments with `tea issues -R <forgejo-remote> --comments -o json <issue-number>`.
     4. Extract the latest handoff comment if present.
        - Prefer the exact `<!-- AI-HANDOFF -->` marker when available.
        - If JSON comments are unavailable, fall back to rendered `tea issues --comments` output and use the visible `**AI-HANDOFF**` heading plus the adjacent status block.
     5. If local `tea` does not return usable comment text, say that clearly and continue from issue body + PR state + branch state.
     6. Check for an open or merged PR related to the issue branch.
     7. Check the current branch and working tree state. A merge or rebase left in flight — unmerged paths, conflict markers, a `REBASE_HEAD` — is the first thing to finish: call the Skill tool with `resolving-merge-conflicts` before any implementation work.
     8. Summarize:
        - issue
        - handoff status
        - expected branch vs current branch
        - linked PR
        - next recommended step

     Status-driven action:
     9. Based on the handoff status, take the appropriate action:
        - `planned` → If implementation was requested or assigned by the parent, proceed in the assigned worktree; otherwise clarify the intended next action.
        - `in-progress` → Continue building from where the last session left off.
        - `blocked` → Surface blockers, ask what to do.
        - `ready-for-commit` / `ready-for-pr` → Suggest `/ship`.
        - `pr-open` / `merged` → Suggest `/complete`.
     10. If the parent issue has sub-issues, list them and recommend working on the next unblocked sub-issue — one whose `**Blocked by:**` line is `none` or references only closed issues.
     11. Prepare an isolated worktree when needed for assigned work; preserve the user's current branch and unrelated changes.

     During implementation:
     - Follow the acceptance criteria from the issue as your checklist.
     - For feature work or bug fixes with testable behaviour, load the `tdd` skill and work its red → green loop over the seams the issue pins (or agree them with the user first).
     - When designing or reshaping a module's interface, consult the `codebase-design` skill for the vocabulary and principles.
     - At natural checkpoints, record concise progress without stopping already-authorized implementation. Workers report to the parent; the parent posts handoffs within the task's authorization.
     - Keep commits granular; do not bundle unrelated changes.
     - When implementation is complete and tests pass, suggest `/ship`.

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
