let
  tea = (import ../templates.nix).teaConventions;
in
{
  name = "brainstorm";
  version = "2.1.0";
  description = "Start a Forgejo-first workflow for new work. Two-phase process: grill the idea with questions, then plan the issue — or map the fog with investigation issues.";
  "argument-hint" = "[initial idea]";
  "disable-model-invocation" = true;
  allowed-tools = [
    "Read"
    "Grep"
    "Glob"
    "Bash"
    "Task"
    "Skill"
  ];
  content = ''
    Start with the current repo only. Do not scan other repositories.

    Goal: refine the user's idea into one Forgejo issue in this repo through two explicit phases — Grill (question everything) and Plan (draft the issue). When the territory is too foggy to plan, emit investigation issues instead of faking certainty.

     Hard rules:
     - Do not propose an issue body or architecture until the user confirms the shared understanding summary.
     - When scope is large, note proposed vertical slices in the issue body.
     - Suggest `/workon` for implementation — brainstorming itself writes no code and changes no files.
     - Ask before creating or updating the issue.
     - Ask before switching branches.
     - If a Jira key appears, enrich with a narrow query only. Never run a broad Jira search.

    ${tea}

    ═══════════════════════════════════════
    PHASE 1 — GRILL (interview & challenge)
    ═══════════════════════════════════════

    Purpose: interview the user relentlessly to build a shared understanding before proposing anything.

    1. Check git remotes and confirm this repo uses Forgejo/Gitea.
    2. Lightly inspect repo context and recent work patterns.
    3. Walk a "design tree" — at each decision point, surface alternatives and trade-offs.
    4. Challenge scope: "Is X needed for v1? What's the simplest thing that works?"
    5. Cover ALL of these question categories before moving to Phase 2:
       - Users & access: who uses this, what permissions?
       - Scope boundaries: what's v1 vs later?
       - Architecture trade-offs: what are the alternatives? why this approach?
       - Integration points: what does this connect to?
       - Data model / core entities: what are the key objects?
       - Failure modes and recovery: what can go wrong?
       - Testing strategy: how do we verify it works?
       - Deployment: how does it ship?
    6. Ask minimum 5-8 questions before proposing anything. One focused question at a time.
    7. End Phase 1 with a "shared understanding" summary:
       - State the problem, the proposed approach, key decisions made, and what's explicitly out of scope.
    8. Fog check — before asking for confirmation, name any material unknowns that questioning could not burn down: unmapped code areas, unverified external behaviour, missing measurements, assumptions nobody can confirm.
       - Clear enough → ask: "Does this shared understanding capture what we want? Confirm to proceed to planning."
       - Foggy → say plainly that planning now would fake certainty, and offer investigation issues instead: one issue per unknown, each stating the question to answer and a "done when we know X" criterion. On approval create them via `tea`, post no plan, and stop — suggest `/workon` on an investigation issue to burn down the fog first.
    9. Do NOT proceed to Phase 2 until the user explicitly confirms the shared understanding.

    ═══════════════════════════════════════
    PHASE 2 — PLAN (draft the issue)
    ═══════════════════════════════════════

    Only enter after user confirms Phase 1 shared understanding.

    10. Search only this repo's open issues for likely duplicates.
    11. If a likely duplicate exists, show it and ask whether to reuse it.
    12. Draft the issue with these sections filled from the grill phase:
        - goal
        - why
        - in scope
        - out of scope
        - acceptance criteria (specific, testable, one per line)
        - implementation notes
        - milestone
    13. If scope is large, add a "Proposed vertical slices" section in the issue body noting how work could be split for `/plan-to-issues`.
    14. Propose:
        - issue title
        - issue body
        - milestone
        - branch name
        - PR title format
    15. Ask whether to create or update the issue.
    16. After the issue exists, ask whether to switch to the issue branch.
        - If the working tree is dirty, recommend a worktree instead of switching.

    ═══════════════════════════════════════
    IMPLEMENTATION GATE
    ═══════════════════════════════════════

    17. After the issue exists, present exactly three options:
        a) "Start implementation" → suggest running `/workon <issue-number>`
        b) "Post plan and stop" → post `AI-HANDOFF` with status `planned`, stop
        c) "Keep refining" → go back to Phase 1 grill

    Issue body shape:
    - `## Цель`
    - `## Почему`
    - `## Входит в scope`
    - `## Вне scope`
    - `## Критерии готовности`
    - `## Заметки по реализации`
    - `## Milestone / связанный контекст`

    Naming:
    - branch: `issue-<forgejo-issue>-<tpl-if-any>-<slug>`
    - PR title: `#<forgejo-issue> <TPL-if-any> <human title>`
    - PR body should later include `Closes #<forgejo-issue>`

     Handoff policy:
     - Post `AI-HANDOFF` only when stopping, blocked, before commit approval, or before PR approval.
     - Use append-only comments; latest handoff wins.
     - Prefer delegating comment creation to the handoff helper when available; otherwise use `tea comment` directly.
     - Planning mode alone is no reason to avoid `tea comment` — skip it only when the runtime explicitly blocks that command.
     - Include a **Decision log** in handoffs summarizing key decisions and their rationale from the grill phase.

     If the user supplied initial context, treat it as the starting idea:
     $ARGUMENTS
  '';
}
