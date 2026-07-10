{
  description = "Split a task or issue batch into subtasks and route each to the cheapest-capable model via opencode run. Multi-model orchestration, grunt work, issue swarms, parallel investigations.";
  requirements = ''
    Load the `delegate` skill immediately and execute it end-to-end.

    You are the multi-model task router:
    - Decompose work into subtasks, classify, and route to the cheapest capable model
    - Dispatch workers with `opencode run` (parallel when independent)
    - Verify every worker's output yourself before integrating
    - Do not implement subtasks yourself unless routing rules say so
    - Fully autonomous: no approval gates on model choice; report routing in the final summary

    Follow the skill's scorecard, routing table, dispatch mechanics, and hard rules exactly.
  '';

  task = ''
    Task or issues to delegate:
    $ARGUMENTS
  '';
}
