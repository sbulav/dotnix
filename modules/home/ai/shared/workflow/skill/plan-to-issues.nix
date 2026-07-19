let
  tea = (import ../templates.nix).teaConventions;
in
{
  name = "plan-to-issues";
  version = "1.1.0";
  description = "Break a planned Forgejo issue into sub-issues — vertical slices for features, expand-contract phases for wide refactors. Use with a parent issue number.";
  "argument-hint" = "[parent-issue-number]";
  "disable-model-invocation" = true;
  allowed-tools = [
    "Read"
    "Grep"
    "Glob"
    "Bash"
    "Task"
  ];
  content = ''
    Break a planned Forgejo issue into sub-issues using only the current repo.

     Hard rules:
     - Read the parent issue body and latest AI-HANDOFF first.
     - Explore the codebase to validate the plan against existing code.
     - Propose all slices at once before creating any.
     - Each slice needs: goal, in-scope, acceptance criteria, a `**Blocked by:**` line, parent reference.
     - Ask one confirmation before creating all sub-issues.
     - Create issues only after user confirmation, via `tea`.

    ${tea}

    Slicing modes — pick per parent issue, and say which you picked and why:

    - **Vertical slices** (default, for feature work): each slice cuts a narrow but complete path
      through every layer it touches (API/logic/storage/tests) and delivers observable behaviour
      on its own. A slice that only builds one horizontal layer is a smell.
    - **Expand-contract** (for wide refactors with high blast radius — renaming a concept across
      many files, swapping a library, changing a schema): slice by phase instead.
      1. *Expand* — introduce the new form alongside the old; nothing breaks.
      2. *Migrate* — move call sites over in reviewable batches (one slice per batch).
      3. *Contract* — remove the old form once nothing references it.
      Each phase keeps CI green on its own, so slices stay independently mergeable.

    Workflow:
    1. Resolve parent issue from `$ARGUMENTS` or current branch.
    2. Fetch parent issue with `tea issues -R <forgejo-remote> <issue-number>`.
    3. Fetch comments with `tea issues -R <forgejo-remote> --comments -o json <issue-number>`.
    4. Extract the latest AI-HANDOFF and read the parent issue body.
    5. Explore the codebase to find existing patterns, validate assumptions, and identify integration points.
       - If a read-only explorer subagent is available, delegate this exploration to it and work from its summary; otherwise explore directly with the read-only tools.
    6. Pick the slicing mode (vertical or expand-contract) and draft slices. Each slice should be:
       - Small enough to implement in one focused session
       - Independently mergeable (complete vertical path, or a CI-green expand-contract phase)
       - Has its own acceptance criteria expressed as `- [ ]` checkboxes
       - Declares blockers: which other slices must land first, or none
       - Tagged with an execution mode: HITL (needs human review or decisions mid-flight) or AFK (safe to run autonomously end-to-end)
    7. Present all slices to the user in a numbered list with:
       - Slice title
       - Goal (1 sentence)
       - What's in scope
       - Acceptance criteria as `- [ ]` checkboxes
       - Execution mode: HITL or AFK
       - Blocked by: slice numbers, or "none — can start immediately"
    8. Ask one confirmation: "Create all N sub-issues? (y/n)"
    9. Create sub-issues **in dependency order** (blockers first), title format: `#<parent> slice: <title>`, so each `**Blocked by:**` line can reference the real issue numbers already created.
       - Apply the `hitl` or `afk` label matching each slice's execution mode.
       - Apply the `ready-for-agent` label to every slice whose blockers are all closed or empty — these are safe targets for `/workon` or `/delegate` swarms. Check `tea labels` first and create missing labels before use.
    10. Post AI-HANDOFF on parent issue with status `planned`, listing all created sub-issue numbers and their blocking edges.

    Sub-issue body shape:
    - `## Цель`
    - `## Входит в scope`
    - `## Режим` (HITL или AFK)
    - `## Критерии готовности` — list each criterion as a `- [ ]` checkbox
    - `## Зависимости`
       first line: `**Blocked by:** #<n>, #<m>` or `**Blocked by:** none — can start immediately`
    - `## Родительский issue`
       `#<parent-number>`

    Input:
    $ARGUMENTS
  '';
}
