{
  name = "complete";
  version = "1.0.0";
  description = "Close out a merged issue workflow in the current repo. Closes the issue and optionally closes the milestone if nothing is left open.";
  "disable-model-invocation" = true;
  allowed-tools = [
    "Read"
    "Grep"
    "Glob"
    "Bash"
    "Task"
  ];
  content = ''
    Finish work after a PR merge in the current repo.

     Hard rules:
     - Only close the issue after the relevant PR is merged.
     - Only close a milestone if it has no open issues left in this repo.
     - Ask before closing a milestone.
     - Ask before deleting branches.
     - If delivery is partial, keep the issue open and post a fresh handoff instead.
     - Use `tea comment -R <forgejo-remote> <issue-number> $'...'` for final handoff comments.
     - Never use `tea issue comment`, `tea api`, or `python3` for normal Forgejo workflow.

     Steps:
     1. Resolve the issue from the current branch, the latest PR, or `$ARGUMENTS`.
     2. Verify the related PR is merged.
     3. Close the issue if still open.
     4. Post a final handoff with status `merged` using `tea comment`.
        - Include both `<!-- AI-HANDOFF -->` and a visible `**AI-HANDOFF**` heading.
     5. If the issue has a milestone, check whether any open issues remain in that milestone in this repo.
     6. Ask whether to close the milestone if it is empty.
     7. Offer optional branch or worktree cleanup.

    Input:
    $ARGUMENTS
  '';
}
