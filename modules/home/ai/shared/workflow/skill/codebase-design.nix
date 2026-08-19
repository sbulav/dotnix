# Adapted from mattpocock/skills `codebase-design` (plugin v1.2.3) — the
# deep-module glossary with banned synonyms, deepening dependency categories
# (DEEPENING.md) and design-it-twice (DESIGN-IT-TWICE.md) folded in condensed,
# retargeted at AGENTS.md vocabulary and the multi-model `delegate` swarm.
{
  name = "codebase-design";
  version = "1.0.0";
  description = "Shared vocabulary and principles for designing deep modules. Use when designing or reshaping a module's interface, deciding where a seam goes, judging whether an abstraction earns its keep, making code more testable or AI-navigable, or when another skill (tdd, delegate-review) needs the module/interface/seam/depth vocabulary.";
  allowed-tools = [
    "Read"
    "Grep"
    "Glob"
    "Bash"
    "Task"
  ];
  content = ''
    Design **deep modules**: a lot of behaviour behind a small interface, placed
    at a clean seam, testable through that interface. This skill is a reference
    to consult, not a session to run — use its language wherever code is being
    designed or restructured. The aim is leverage for callers, locality for
    maintainers, and testability for everyone.

    Before proposing any reshape, read AGENTS.md if it exists: name things with
    its `## Vocabulary`, and check `## Decisions` — the design you are about to
    propose may already be recorded there as rejected, with the reason.

    ## Glossary

    Use these terms exactly — don't substitute "component", "service", "API",
    or "boundary". Consistent language is the whole point.

    - **Module** — anything with an interface and an implementation.
      Deliberately scale-agnostic: a function, class, package, or tier-spanning
      slice. *Avoid:* unit, component, service.
    - **Interface** — everything a caller must know to use the module
      correctly: the type signature, but also invariants, ordering constraints,
      error modes, required configuration, and performance characteristics.
      *Avoid:* API, signature (too narrow — type-level surface only).
    - **Implementation** — what's inside a module, its body of code.
    - **Depth** — leverage at the interface: how much behaviour a caller (or
      test) can exercise per unit of interface they must learn. **Deep** =
      small interface, lots of implementation. **Shallow** = interface nearly
      as complex as the implementation (a pass-through).
    - **Seam** *(Michael Feathers)* — a place where you can alter behaviour
      without editing in that place; the *location* where a module's interface
      lives. Where the seam goes is its own design decision, distinct from what
      goes behind it. *Avoid:* boundary (overloaded with DDD's bounded
      context).
    - **Adapter** — a concrete thing that satisfies an interface at a seam.
      Describes *role* (what slot it fills), not substance. A thing can be a
      small adapter with a large implementation (a Postgres repo) or a large
      adapter with a small implementation (an in-memory fake).
    - **Leverage** — what callers get from depth: one implementation pays back
      across N call sites and M tests.
    - **Locality** — what maintainers get from depth: change, bugs, knowledge,
      and verification concentrate in one place. Fix once, fixed everywhere.

    When designing an interface, ask: can I reduce the number of methods? Can I
    simplify the parameters? Can I hide more complexity inside?

    ## Principles

    - **Depth is a property of the interface, not the implementation.** A deep
      module can be internally composed of small, swappable parts — they just
      aren't part of the interface. Internal seams (private, used by the
      module's own tests) are fine; don't expose them through the interface
      just because tests use them.
    - **The deletion test.** Imagine deleting the module. If complexity
      vanishes, it was a pass-through. If complexity reappears across N
      callers, it was earning its keep.
    - **The interface is the test surface.** Callers and tests cross the same
      seam. If you want to test *past* the interface, the module is probably
      the wrong shape.
    - **One adapter means a hypothetical seam. Two adapters means a real one.**
      Don't introduce a seam unless something actually varies across it
      (typically production + test). A single-adapter seam is just indirection.

    ## Designing for testability

    1. **Accept dependencies, don't create them** — take the gateway/client as
       a parameter instead of constructing it inside.
    2. **Return results, don't produce side effects** — `calculateDiscount(cart)
       -> Discount` beats `applyDiscount(cart) -> void` mutating in place.
    3. **Small surface area** — fewer methods means fewer tests needed; fewer
       params means simpler test setup.

    ## Deepening a cluster of shallow modules

    Classify the cluster's dependencies first — the category determines how the
    deepened module is tested across its seam:

    1. **In-process** (pure computation, in-memory state): always deepenable —
       merge and test through the new interface directly, no adapter.
    2. **Local-substitutable** (a local test stand-in exists: PGLite,
       in-memory filesystem): deepen and test with the stand-in; the seam stays
       internal.
    3. **Remote but owned** (your own services over the network): define a port
       at the seam; production gets an HTTP/gRPC/queue adapter, tests an
       in-memory one — the logic sits in one deep module even though it's
       deployed across a network.
    4. **True external** (Stripe, Twilio — not yours): inject the dependency as
       a port; tests provide a mock adapter. Mock only here — never your own
       modules.

    **Replace, don't layer:** once tests exist at the deepened module's
    interface, the old unit tests on the swallowed shallow modules are waste —
    delete them. Tests that must change when the implementation changes were
    testing past the interface.

    ## Design it twice

    Your first interface idea is unlikely to be the best (Ousterhout). For a
    non-trivial deepening candidate: frame the problem space for the user
    (constraints, dependencies and their category above, a grounding sketch),
    then spawn 3+ parallel agents, each briefed to produce a **radically
    different** interface — one minimizing the surface (1–3 entry points, max
    leverage each), one maximizing flexibility, one optimizing the most common
    caller, and where cross-seam dependencies exist, one built around ports &
    adapters. When the `delegate` skill is in play, route the briefs to
    different model families — model diversity is free design diversity. Each
    brief carries this glossary plus AGENTS.md `## Vocabulary`. Compare the
    results on **depth**, **locality**, and **seam placement**, then give one
    opinionated recommendation (hybrids allowed) — the user wants a strong
    read, not a menu.

    ## Rejected framings

    - **Depth as implementation-lines over interface-lines**: rewards padding
      the implementation. Depth-as-leverage instead.
    - **"Interface" as the language keyword or a class's public methods**: too
      narrow — interface here is every fact a caller must know.
    - **"Boundary"**: overloaded. Say **seam** or **interface**.
  '';
}
