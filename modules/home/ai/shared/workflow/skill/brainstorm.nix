{
  name = "brainstorm";
  version = "2.0.0";
  description = "Start a Forgejo-first workflow for new work. Two-phase process: grill the idea with questions, then plan the issue.";
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

    Goal: refine the user's idea into one Forgejo issue in this repo through two explicit phases — Grill (question everything) and Plan (draft the issue).

     Hard rules:
     - Do not propose an issue body or architecture until the user confirms the shared understanding summary.
     - When scope is large, note proposed vertical slices in the issue body.
     - Never start implementation directly — suggest `/workon` instead.
     - Do not write code or change files during brainstorming.
     - Ask before creating or updating the issue.
     - Ask before switching branches.
     - When listing issues, only query the current repo via `tea` from the current working tree.
     - Use `tea comment -R <forgejo-remote> <issue-number> $'...'` for handoff comments.
     - Never use `tea issue comment`, `tea api`, or `python3` for normal Forgejo workflow.
     - If a Jira key appears, enrich with a narrow query only. Never run a broad Jira search.

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
       - Ask: "Does this shared understanding capture what we want? Confirm to proceed to planning."
    8. Do NOT proceed to Phase 2 until the user explicitly confirms the shared understanding.

    ═══════════════════════════════════════
    PHASE 2 — PLAN (draft the issue)
    ═══════════════════════════════════════

    Only enter after user confirms Phase 1 shared understanding.

    9. Search only this repo's open issues for likely duplicates.
    10. If a likely duplicate exists, show it and ask whether to reuse it.
    11. Draft the issue with these sections filled from the grill phase:
        - goal
        - why
        - in scope
        - out of scope
        - acceptance criteria (specific, testable, one per line)
        - implementation notes
        - milestone
    12. If scope is large, add a "Proposed vertical slices" section in the issue body noting how work could be split for `/plan-to-issues`.
    13. Propose:
        - issue title
        - issue body
        - milestone
        - branch name
        - PR title format
    14. Ask whether to create or update the issue.
    15. After the issue exists, ask whether to switch to the issue branch.
        - If the working tree is dirty, recommend a worktree instead of switching.

    ═══════════════════════════════════════
    IMPLEMENTATION GATE
    ═══════════════════════════════════════

    16. After the issue exists, present exactly three options:
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
     - If you need to post a handoff here, do it with `tea comment` only.
     - Prefer delegating comment creation to the handoff helper when available; otherwise use `tea comment` directly.
     - Include both the hidden `<!-- AI-HANDOFF -->` marker and a visible `**AI-HANDOFF**` heading.
     - If runtime mode or permissions block writes, do not investigate tokens or API auth; return the exact handoff body for manual posting.
     - Do not treat planning mode as a reason to avoid `tea comment` unless the runtime explicitly blocks that command.
     - For `tea comment`, prefer a single safely quoted argument such as `$'...'`; avoid heredocs, command substitution, or backgrounded comment commands.
     - Never include system reminders, tool diagnostics, or internal policy text inside the handoff body.
     - Include a **Decision log** in handoffs summarizing key decisions and their rationale from the grill phase.

     If the user supplied initial context, treat it as the starting idea:
     $ARGUMENTS
  '';
}
