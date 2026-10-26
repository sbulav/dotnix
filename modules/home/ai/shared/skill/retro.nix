# Adapted from mattpocock/skills `retro` (v1.3.1, reviewed at 5beb35b) — the
# environment-not-code retrospective and its mechanical/judgement split,
# retargeted at this repo's steering files (CLAUDE.md / AGENTS.md), its CI
# guardrail, and Nix-rendered skills instead of CODING_STANDARDS.md.
{
  name = "retro";
  version = "1.0.0";
  description = "Retrospective on a coding session: propose changes to the agent's environment, not to the code it wrote.";
  "argument-hint" = "[session to review; empty for the current one]";
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
    The user asked for a **retrospective**. The deliverable is a ranked list of
    changes to the **environment** the next run starts from — pointers, checks,
    steering lines, tooling, access — never to the code this session wrote.
    Nothing is edited during a retro.

    ## Steps

    1. Call the Skill tool with `writing-for-agents`. Every proposal that
       lands in a steering file or a skill is judged by its rules: the no-op
       test, context-pointer wording, cache versus environment.

    2. Read the primary sources. Default to the current session; a named one
       lives in the harness's session logs on this machine (Claude Code keeps
       them under `~/.claude/projects/<cwd-slug>/`). Read the repo's own
       **guardrail** before judging anything: its CI workflow and check
       command (here `nix flake check`, statix, deadnix and `checks/`), so a
       check that exists but is unwired or silently broken is the finding,
       not a reinvention. Done when every place the session stalled, retried,
       guessed, or was corrected is listed with its cost in turns.

    3. Classify each stall into one category, or an explicit "no environment
       fix":

       - **Navigation** — the agent took long to find a file, a fact, or a
         hidden dependency between files. Fix: a **navigation pointer** in the
         steering file or a skill description, worded to fire on that branch.
       - **Automated checks** — a mistake a linter, type check, test, or
         filesystem check would have caught. A repo with no guardrail at all
         (no CI job and no hook running its lint/check/test command) is itself
         a finding: an unchecked repo is a standing missed opportunity.
       - **Coding standards** — a convention the reviewer should enforce, or
         an existing rule to drop or sharpen. Classify first: a **mechanical**
         violation (a fixed pattern, a banned API, an import shape, a file
         location) gets a deterministic check — a `checks/` derivation, a
         statix/deadnix setting, a CI job, whichever is cheapest here — and
         the steering file stays silent about it. A **judgement** call
         (cross-file consistency, matching the surrounding style) gets a line
         in the conventions `delegate-review` reads. Default to building the
         check.
       - **Steering files** — lines in CLAUDE.md / AGENTS.md that belong in a
         check or in a doc reached by a pointer, and **no-op** lines: a
         sentence that leaves behaviour unchanged against the default is
         deleted whole, not trimmed.
       - **Tool economy** — an expensive or repeated tool call, or custom
         tooling (a CLI, an MCP server) that is token-heavy for what it
         returns.
       - **Information access** — a fact the agent could not reach: a log it
         could have tailed, a service it could have read, a dev server it
         could have watched.

       Done when every stall carries a category.

    4. Present the candidates to the user in order of severity. For each:
       the evidence from the session and its cost, the proposed change, where
       it lands, and whether it is mechanical or judgement. Then stop — the
       user chooses. A chosen candidate larger than a one-line edit goes
       through `brainstorm` to become an issue; a one-line edit the user
       approves is made in that same turn.

    ## Reference

    **Implementation versus review.** The implementing agent carries the
    most **context pressure**: exploration, writing, debugging. The reviewer
    carries the least: it receives a diff. So standards are enforced at
    review, and a retro that puts a rule on the implementer is usually
    putting it in the wrong place.

    **Where things live here.**
    - CLAUDE.md / AGENTS.md is pushed into every agent's context: sparingly,
      mostly navigation pointers and the gotchas no file confesses.
    - Review conventions are what `delegate-review` collects from the repo's
      documented-conventions files; a judgement rule goes there.
    - Deterministic checks are `checks/`, statix, deadnix, and the CI
      workflow; a mechanical rule goes there.
    - Skills are `modules/home/ai/shared/skill/` and
      `modules/home/ai/shared/workflow/skill/`: a doc whose description must
      trigger on its own is model-invoked; a command is user-invoked.

    Input: $ARGUMENTS
  '';
}
