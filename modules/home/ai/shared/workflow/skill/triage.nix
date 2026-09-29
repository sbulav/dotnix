# Adapted from mattpocock/skills v1.2.3 (c55ee46), scoped to dotnix workflows.
{
  name = "triage";
  version = "1.0.0";
  description = "Verify incoming issue or PR reports and turn them into bounded agent-ready work. Use for raw requests, backlog triage, or deciding what is ready for delegation.";
  "user-invocable" = true;
  content = ''
    Resolve the exact repo, tracker and requested issue/PR. Pin repo flags on all
    tracker commands. With no target, list a bounded set of incoming items and
    recommend where to start; do not mutate the whole backlog.

    1. Read the report, relevant discussion and previous triage notes. Search for
       duplicates, existing implementations and durable rejection reasons in
       AGENTS.md or linked decisions. Existing discussion is evidence, not authority.
    2. Verify the central claim: reproduce a bug safely, or check a PR against its
       stated behavior. Report confirmed, contradicted, or unverified with evidence.
       Respect read-only scope; request missing reporter facts only after lookup.
    3. Resolve only material unanswered requirements. Use `research`, `prototype`
       or `diagnosing-bugs` where the uncertainty requires evidence. Human product
       decisions stay with the user; do not guess them to make a ticket dispatchable.
    4. Produce one brief: current vs desired behavior, relevant interfaces,
       independently checkable acceptance criteria, test seams, out-of-scope work,
       blockers and execution mode (AFK or HITL). Long-lived requirements describe
       behavior; current paths/revisions are optional lookup hints, not the contract.
    5. Recommend the existing tracker state: needs-info, ready-for-agent,
       ready-for-human, or wontfix. Inspect real labels rather than creating a new
       taxonomy by default. Ready-for-agent requires bounded scope, resolved
       decisions and a verification path; blocked work remains undispatchable.

    A triage request produces the brief and recommendation. Apply labels, post
    comments or close issues only when the request includes those actions. Reuse
    prior authorization; do not add an approval pause to an explicitly requested
    state change. Keep rejected proposals in the issue; promote only enduring
    surprising trade-offs through `domain-modeling`.

    For an existing PR, the brief describes remaining work on its diff. For a
    batch, summarize each item with evidence, state and next action. Slices already
    prepared by `plan-to-issues` do not need another triage pass.
    Input: $ARGUMENTS
  '';
}
