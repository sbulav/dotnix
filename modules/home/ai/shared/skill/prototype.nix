# Adapted from mattpocock/skills v1.2.3 (c55ee46), scoped to dotnix workflows.
{
  name = "prototype";
  version = "1.0.0";
  description = "Build a disposable experiment to answer a specific design question, such as state behavior, integration feasibility, or UI alternatives.";
  "user-invocable" = true;
  content = ''
    Name the question and the observation that would resolve it before writing
    code. If the question is ambiguous, inspect context and clarify only the
    choice that would materially change the experiment.

    Use an isolated worktree or a clearly named task-owned scratch directory.
    Keep it runnable with one command, local fixtures, and visible relevant state.
    For a UI question, show a few meaningfully different options; for logic, expose
    transitions and edge cases; for integration, demonstrate the smallest real
    interaction within the user's authorization. Use synthetic/redacted data.

    Spend only enough on tests and structure to trust the observation. Prefer
    in-memory state; never use production mutations as experimental scaffolding.
    Mark the result as a prototype so it cannot be mistaken for production code.

    Report the question, how to run it, evidence, verdict, uncertainty and what
    should change in the implementation plan. Preserve the artifact and link it
    from the plan or handoff. Commit a prototype branch or post a tracker link
    only if authorized. Keep code out of main until production implementation is
    explicitly requested and properly validated. Stop processes you started when
    finished; leave unrelated services running.
    Input: $ARGUMENTS
  '';
}
