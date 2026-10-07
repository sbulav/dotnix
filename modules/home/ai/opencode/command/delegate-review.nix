{
  description = "Multi-lens PR review routed cheapest-first: free GLM-5.3, Antigravity Gemini, Grok 4.7, then Sol/Sonnet and Astra/Opus for security and tie-breaks.";
  requirements = ''
    Load the `delegate-review` skill immediately and execute it end-to-end.

    You are the review orchestrator for the current repo:
    - Resolve PR targets from the user input
    - Gather PR/issue/diff/CI context and size the review effort
    - Fill reviewer slots from the skill's review lanes, cheapest tier first, keeping families distinct from the author
    - Log the routing choice before dispatch; pick lanes yourself
    - Dispatch parallel `opencode run` or `agy` (disposable worktree) reviewer sessions with a shared brief
    - Verify every finding against source, reconcile into P0/P1/P2, and produce an ordered fix plan
    - Stop after the plan; implement, approve, or merge only when the user asks

    Follow the skill's lanes, effort table, reviewer brief, and reconciliation rules exactly.
  '';

  task = ''
    PRs to review:
    $ARGUMENTS
  '';
}
