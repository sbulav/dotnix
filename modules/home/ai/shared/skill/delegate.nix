let
  routing = (import ../routing.nix).policy;
in
{
  name = "delegate";
  version = "2.0.0";
  description = "Delegate bounded implementation, investigations, or issue batches across available models. Use when independent work benefits from parallel execution, isolated workers, or a second model's review.";
  "argument-hint" = "[task, issue number(s), or repo issue list]";
  "user-invocable" = true;
  allowed-tools = [
    "Bash"
    "Read"
    "Grep"
    "Glob"
    "Write"
    "TodoWrite"
    "Skill"
    "Task"
  ];
  content = ''
    Orchestrate through verified completion. Keep tightly coupled decisions
    and integration in the parent; delegate independent, checkable outputs.

    ## Workflow

    1. Inspect the task, repo instructions, current diff/index, and available
       harnesses. Identify the critical path and work that can run beside it.
       If no useful split exists, complete the task locally.
    2. Give each worker one owned deliverable and an acceptance check. Select
       a model with the shared routing policy below; report the choice briefly.
    3. Dispatch independent tasks concurrently within runtime limits. Work
       on another necessary part locally; avoid duplicating worker searches.
    4. Read each returned diff and verify acceptance evidence against the
       correct repo/revision. Correct or escalate once per the recovery rule.
    5. Integrate, resolve conflicts by intent (`resolving-merge-conflicts`),
       and run the required checks on the integrated state. Report results
       and any remaining blockers. Follow existing authorization for the
       next step; `/ship` remains user-invoked.

    ${routing}

    ## Issue batches

    Resolve tracker and repo explicitly. Read acceptance criteria, assignees,
    and `Blocked by` dependencies; skip claimed or blocked issues. Claim work
    through the tracker only when authorized; otherwise keep the allocation
    local. Give each editing worker its own worktree and a branch matching
    repo convention. Serialize issues that overlap or depend on each other.

    Give workers the issue brief directly. If invoking `workon`, state that
    implementation in this prepared worktree is already assigned, and that
    handoffs and shipping belong to the parent. Workers stop after changes
    and validation. The parent reviews spec compliance and code correctness
    independently, then verifies the integrated result. Use `delegate-review`
    when an additional model's substantive review is justified.

    Recompute the unblocked frontier after each completed wave. A task that
    explicitly includes commits/push/PR creation authorizes those steps;
    otherwise return ready changes and suggest `/ship`. Check the index before
    each commit and pin repo targets on every tracker operation. Never merge
    or activate a host merely because implementation was delegated.

    Final batch report: issue, worker/model, validation, review outcome,
    branch/PR if created, and blocker. Remove only task-owned scratch files
    and worktrees whose changes are safely retained.

    Input: $ARGUMENTS
  '';
}
