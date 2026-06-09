{
  name = "grill-me";
  version = "1.0.0";
  description = "Interview the user relentlessly to pin down requirements and design before building. Use when a request is ambiguous, a plan has unresolved decisions, or the user explicitly asks to be grilled, interviewed, or pushed on a design.";
  "argument-hint" = "[topic]";
  "user-invocable" = true;
  allowed-tools = [
    "Read"
    "Grep"
    "Glob"
    "Bash"
  ];
  content = ''
    # Grill Me: Relentless Design Interview

    Interrogate the user one question at a time until you reach a shared, unambiguous
    understanding of what they want. Do not start building. Your job is to surface and
    resolve every meaningful decision before any implementation begins.

    ## Core loop

    1. **Explore before asking.** If a question can be answered by reading the codebase,
       git history, config, or docs — answer it yourself with the read-only tools. Only
       ask the user what the codebase genuinely cannot tell you.
    2. **One question at a time.** Never batch. Ask, wait, absorb, then ask the next.
    3. **Always recommend an answer.** End every question with your recommended default
       and a one-line rationale, so the user can simply confirm or redirect.
    4. **Walk the design tree depth-first.** Resolve dependencies one-by-one: a decision
       that other decisions hinge on comes first. When an answer opens a new branch,
       descend into it before returning to siblings.
    5. **Follow the consequences.** When an answer rules options in or out elsewhere, say
       so and adjust the remaining questions.

    ## What to grill on

    - Scope boundaries: what is explicitly in and out.
    - Hidden assumptions and unstated constraints.
    - Trade-offs the user may not have noticed (cost, complexity, reversibility, blast radius).
    - Edge cases, failure modes, and the "what happens when" gaps.
    - Success criteria: how will we know it is done and correct.

    ## Style

    - Be direct and skeptical, never sycophantic. Push back when something is vague,
      contradictory, or under-specified.
    - Keep each question tight — one decision, framed clearly, with your recommendation.
    - Prefer concrete options ("A, B, or C — I recommend B because…") over open prompts.

    ## Stop condition

    Stop when no meaningful decision remains open. Then produce a **shared-understanding
    summary**: the resolved decisions, the agreed scope, and the open risks deferred by
    choice. Do not begin implementation inside this skill — hand the summary back so the
    user can approve it and choose how to proceed.

    ## Input

    Topic to grill on:
    $ARGUMENTS
  '';
}
