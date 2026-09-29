# Adapted from mattpocock/skills v1.2.3 (c55ee46), scoped to dotnix workflows.
{
  name = "dev";
  version = "1.0.0";
  description = "Choose and run the appropriate development workflow. Use when the user asks which development skill to use or explicitly invokes dev with a task.";
  "user-invocable" = true;
  content = ''
    Route the user's request to the smallest useful workflow, then perform it.
    Read repo instructions, remotes and current changes before choosing a route.
    State the route in one sentence. Load only skills needed for the current phase,
    using the harness skill loader or reading the installed SKILL.md directly.
    A clear request to implement already authorizes implementation; choosing a
    route does not authorize publishing, merging, deployment, or unrelated work.

    ## Routes

    - Small, specified edit: implement directly and run relevant checks. No issue,
      interview, or worker is required. Use `tdd` for behavior that warrants a test.
    - Existing issue: `workon`, with its acceptance criteria and assigned worktree.
    - Unclear feature: `brainstorm`; investigate facts yourself, ask only decisions
      that materially affect the result. Do not re-ask settled questions.
    - Unknown external behavior: `research`. A question needing executable evidence
      or a visual comparison: `prototype`. Feed the answer back into planning.
    - Multi-session feature: `plan-to-issues` after the parent issue has a clear
      goal; use vertical slices or expand-contract phases with explicit blockers.
    - Incoming raw bug/feature report: `triage`. Already prepared slices skip triage.
    - Hard bug or regression: `diagnosing-bugs` before speculative patches.
    - Independent implementation tasks: `delegate`; retain integration locally.
    - PR/branch correctness or spec check: `delegate-review`.
    - Requested architecture survey: `architecture-review`; implementation waits
      for a selected, scoped candidate.
    - Ready changes: suggest `ship`. It remains user-invoked, not an automatic phase.
    - Explicitly requested post-merge cleanup: `complete`.

    ## Context between phases

    Continue in the same session while its reasoning is useful. Start a fresh
    worker for a self-contained issue or an independent review. Use `handoff`
    when changing harness, directory, or collaborator; preserve decisions by
    linking primary artifacts. Compact at a phase boundary when space is needed;
    use the runtime's actual context indicators, not a fixed token threshold.
    Clear only when the next task does not need the current context.

    If a skill is absent, use its installed file if readable; otherwise state
    that limitation and execute the bounded task with available tools. A router
    must not silently invent a command or invoke itself recursively.

    Before declaring implementation complete, compare the diff with acceptance
    criteria and run required checks. Use `delegate-review` for substantive
    independent review when the risk justifies it; a small edit needs no swarm.
    Finish with the outcome, verification, and remaining decision, if any.
    Input: $ARGUMENTS
  '';
}
