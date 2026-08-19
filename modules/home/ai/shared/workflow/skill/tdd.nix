# Adapted from mattpocock/skills `tdd` (plugin v1.2.3) — pre-agreed seams,
# the tautological-test ban, and vertical tracer-bullet slices (tests.md and
# mocking.md folded in condensed), extended with an AFK rule so delegated
# workers take seams from the issue instead of blocking on a user.
{
  name = "tdd";
  version = "1.0.0";
  description = "Test-driven implementation: the red-green loop over pre-agreed seams. Use when implementing a feature or fixing a bug with testable behaviour — issue work via workon or a delegated worker session — or when the user mentions TDD, red-green, test-first, or integration tests.";
  allowed-tools = [
    "Read"
    "Grep"
    "Glob"
    "Bash"
    "Task"
    "Edit"
    "Write"
    "Skill"
  ];
  content = ''
    TDD is the red → green loop. This skill is the reference that makes the
    loop produce tests worth keeping: what a good test is, where tests go, the
    anti-patterns, and the rules of the loop. Every section applies on every
    cycle — consult them before and during the loop, not after.

    When exploring the codebase, read AGENTS.md if it exists so test names and
    interface vocabulary match its `## Vocabulary`, and respect the entries in
    `## Decisions` for the area you're touching.

    ## What a good test is

    Tests verify behaviour through public interfaces, not implementation
    details. Code can change entirely; tests shouldn't. A good test reads like
    a specification — "user can checkout with valid cart" says exactly what
    capability exists — uses the public API only, makes one logical assertion,
    describes WHAT rather than HOW, and survives internal refactors.

    ## Seams — where tests go

    A **seam** is the public boundary you test at: the interface where you
    observe behaviour without reaching inside. Tests live at seams, never
    against internals.

    **Test only at pre-agreed seams.** You can't test everything — agreeing the
    seams up front is how testing effort lands on the critical paths and
    complex logic instead of every edge case. No test is written at an
    unconfirmed seam. Where the agreement comes from depends on the session:

    - **User present (HITL):** before writing any test, write down the seams
      under test and confirm them — "what's the public interface, and which
      seams should we test?"
    - **Delegated / AFK worker:** the pre-agreed seams are the ones pinned in
      the issue — a "seams under test" note if the slice has one, otherwise the
      acceptance criteria (each criterion names an observable behaviour; test
      it through the interface that exposes it). Record the seams you settled
      on in the AI-HANDOFF instead of asking, and never quietly widen them to
      internals.

    When the shape of the interface is itself in question — how deep the
    module is, where the seam belongs, what it should expose — call the Skill
    tool with `codebase-design`: it is the shared source of the module,
    interface, depth, seam, adapter, leverage and locality terms.

    ## Anti-patterns

    - **Implementation-coupled** — mocks internal collaborators, tests private
      methods, asserts on call counts/order, or verifies through a side
      channel instead of the interface. The tell: the test breaks on refactor
      though behaviour hasn't changed.

      ```
      BAD:  await createUser({name: "Alice"});
            expect(await db.query("SELECT ... WHERE name='Alice'")).toBeDefined();
      GOOD: const user = await createUser({name: "Alice"});
            expect((await getUser(user.id)).name).toBe("Alice");
      ```

    - **Tautological** — the assertion recomputes the expected value the way
      the code does, so it passes by construction and can never disagree with
      the code. Expected values must come from an independent source of truth:
      a known-good literal, a worked example, the spec.

      ```
      BAD:  expect(calculateTotal(items)).toBe(items.reduce((s, i) => s + i.price, 0));
      GOOD: expect(calculateTotal([{price: 10}, {price: 5}])).toBe(15);
      ```

    - **Horizontal slicing** — writing all tests first, then all
      implementation. Bulk tests verify *imagined* behaviour and commit you to
      test structure before you understand the implementation. Work in
      **vertical slices**: one test → one implementation → repeat, each test a
      **tracer bullet** that responds to what the last cycle taught you.

    ## Mocking

    Mock at **system boundaries only**: third-party APIs, time/randomness,
    sometimes databases and filesystem (prefer a real test stand-in when one
    exists). Never mock your own modules or internal collaborators. Make
    boundaries mockable by design: inject dependencies rather than
    constructing them inside, and prefer SDK-style interfaces (one specific
    function per external operation, each independently mockable) over one
    generic fetcher that forces conditional logic into every mock.

    ## Rules of the loop

    - **Red before green.** Write the failing test first and *see it fail*,
      then only enough code to pass it. No anticipating future tests, no
      speculative features.
    - **One slice at a time.** One seam, one test, one minimal implementation
      per cycle.
    - **Refactoring is not part of the loop.** It belongs to the review stage
      — `/ship`'s pre-commit review or a `delegate-review` pass — not the
      red → green cycle.

    Done when: every acceptance criterion in scope has a test that was seen
    red and is now green (name the test command you ran), and no test exists
    at a seam that wasn't agreed.
  '';
}
