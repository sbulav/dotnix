# Adapted from mattpocock/skills `domain-modeling` (plugin v1.2.3) — the strict
# glossary interview and the 3-part ADR admission test, retargeted at AGENTS.md
# sections instead of CONTEXT.md + docs/adr/, per the lifecycle rule: the
# tracker holds what closes, the repo holds what doesn't.
{
  name = "domain-modeling";
  version = "1.0.0";
  description = "Maintain the repo's durable domain memory in AGENTS.md: a strict vocabulary and a curated decision record. Use when a lasting decision needs recording, domain terms are ambiguous or clash with code names, the user mentions ADR / glossary / decision record, or a handoff decision log needs promotion at ship time.";
  allowed-tools = [
    "Read"
    "Grep"
    "Glob"
    "Bash"
    "Task"
    "Edit"
    "Write"
  ];
  content = ''
    Keep each repo's durable domain memory in **AGENTS.md** — the one file every
    session already loads. Two sections, created on first use:

    - `## Vocabulary` — a strict glossary of domain terms.
    - `## Decisions` — decisions that outlive any single issue.

    Never scaffold `CONTEXT.md` or a `docs/adr/` tree. Only when one decision
    outgrows a paragraph does it move to its own file, leaving a one-line
    pointer in AGENTS.md behind.

    ## What goes where

    The tracker holds what has a lifecycle; AGENTS.md holds what doesn't. Test:
    if "closed" is a meaningful state for it, it belongs in an issue. A decision
    never closes — it only gets superseded.

    ## The admission bar

    A decision earns a line only when it is **all three** of:
    - **Hard to reverse** — changing it later means rework, migration, or a breaking change.
    - **Surprising** — a competent newcomer would plausibly do it the other way.
    - **A real trade-off** — a credible alternative was rejected for a stated reason.

    Rejections count: "we do NOT do X, because Y" prevents relitigating a
    settled argument. Most decisions fail the bar — that is the bar working.
    When in doubt, leave it in the issue's AI-HANDOFF decision log; AGENTS.md is
    for what must outlive the issue.

    ## Decision format

    One entry, one to three lines:

    ```
    - **<decision>** — <why, naming the rejected alternative>. (#<issue>)
    ```

    The issue number carries the full trail — never duplicate the discussion.
    When a later decision supersedes an entry, rewrite the entry in place:
    AGENTS.md states what is true now; git history keeps what was.

    ## Vocabulary format

    One term per line: `- **<term>** — <strict definition>`. A term earns a
    line only when it is ambiguous, domain-specific, or its code name diverges
    from the business name. That divergence is itself a finding — record the
    mapping, or file an issue to rename.

    ## Interviewing (invoked from grill-me / brainstorm)

    For each core entity, put the definition question to the user: "When you
    say X, what exactly is — and is not — an X?" Push until the definition
    excludes something; a definition that excludes nothing defines nothing.
    Where the user's usage contradicts the code's naming, that goes on the
    frontier as a question, never silently into the glossary.

    ## Promotion (invoked from ship)

    Read the issue's latest AI-HANDOFF **Decision log**, test each entry
    against the bar, and write the survivors into AGENTS.md **in the same
    commit as the code** — the decision gets reviewed alongside the change that
    motivated it. Most handoffs promote nothing; skip silently rather than
    lowering the bar to have something to write.
  '';
}
