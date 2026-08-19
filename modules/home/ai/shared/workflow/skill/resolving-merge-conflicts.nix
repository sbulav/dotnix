# Adapted from mattpocock/skills `resolving-merge-conflicts` (plugin v1.2.3) —
# intent archaeology plus the never-abort rule, extended with the AI-HANDOFF
# decision log as a primary source and with `delegate` worktree swarms in mind.
let
  tea = (import ../templates.nix).teaConventions;
in
{
  name = "resolving-merge-conflicts";
  version = "1.0.0";
  description = "Resolve an in-progress git merge or rebase conflict hunk by hunk. Use when a merge, rebase, cherry-pick, or worktree integration stops on conflicts, or the user reports conflict markers, unmerged paths, or a stuck rebase.";
  allowed-tools = [
    "Read"
    "Grep"
    "Glob"
    "Bash"
    "Task"
    "Edit"
    "Write"
  ];
  content = ''
    Resolve an in-flight merge or rebase hunk by hunk, by **intent** — never by picking whichever side makes the markers disappear.

    Hard rule: always resolve; never `--abort`. Aborting discards the reconciliation work and hands the same conflict to the next session. If the merge itself turns out to be wrong, stop and say so — that is the user's call, not an abort you take alone.

    ${tea}

    ## 1 — See the state

    Establish before touching a hunk:
    - Which operation is in flight and how far it got (`git status`).
    - Which files conflict, and which paths are already staged as resolved.
    - What each side actually is: `git log --oneline` over both ranges (`HEAD` vs `MERGE_HEAD`, or the rebase's upstream vs `REBASE_HEAD`).

    Inside a `delegate` worktree swarm the two sides are usually sibling slices of one parent issue. Name the issue for each side — the sub-issues state how the work was split, which is often the whole answer.

    ## 2 — Find the primary sources

    For each conflicting hunk, learn why each side changed that line, in order of authority:
    - The commit that introduced it — read its message, not just its diff.
    - The PR that carried it (`tea pulls`).
    - The issue and its latest AI-HANDOFF (`tea issues --comments`). The handoff **Decision log** is the highest-value source here: it records the decision behind the code, which the diff never shows.

    Resolving a hunk whose intent you have not read is guessing. When both sides are opaque, ask rather than invent.

    ## 3 — Resolve each hunk

    - Preserve both intents wherever they compose.
    - Where they genuinely conflict, keep the one matching the stated goal of this merge — the branch being merged into, the issue being shipped — and record the trade-off for the commit message.
    - Keep the resolution to what the two sides already do. A merge is a reconciliation, not a redesign; behaviour neither side has belongs in a follow-up issue.
    - Deleted-vs-modified and rename conflicts: read the deleting commit and confirm the deletion was deliberate before restoring a file.
    - Generated artifacts (`flake.lock`, lockfiles, rendered manifests): regenerate them from the merged inputs instead of hand-merging the hunk.

    ## 4 — Run the project's checks

    Discover what the repo actually runs rather than assuming — formatter, typecheck, tests, and for this dotfiles repo `nix fmt` plus a build of the affected flake target. Run them and fix what the merge broke.

    A merge that builds is not a merge that works: run the tests covering **both** sides' behaviour, not only the files you edited.

    ## 5 — Finish the operation

    Stage everything and carry the operation to completion — `git commit` for a merge, `git rebase --continue` until every commit is replayed. A rebase will stop again on later commits; work each stop through this same loop.

    **Completion criterion.** No conflict markers survive anywhere in the tree (grep for them), `git status` reports no unmerged paths and no operation in flight, and the project's checks pass. Any trade-off taken in step 3 is stated in the merge commit message, so the next reader learns which intent won and why.
  '';
}
