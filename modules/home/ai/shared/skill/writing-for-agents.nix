# Adapted from mattpocock/skills `writing-for-agents` (v1.2.2, formerly
# `writing-great-skills`) — the reference to consult when writing any document
# an agent consumes. Model-invoked on purpose: it must fire whenever a skill
# or AGENTS.md is being authored, without the user remembering it exists.
{
  name = "writing-for-agents";
  version = "2.0.0";
  description = "Writing documents for agents: skills, AGENTS.md/CLAUDE.md, and any doc an agent reaches by a pointer. Use when creating or editing skills, or modifying AGENTS.md or CLAUDE.md.";
  allowed-tools = [
    "Read"
    "Grep"
    "Glob"
  ];
  content = ''
    Reference for writing any document an agent consumes — a skill, an
    `AGENTS.md` / `CLAUDE.md`, a doc reached by a pointer. The packaging
    differs; the writing does not: the same levers make each one predictable —
    the agent taking the same *process* every run, not producing the same
    output.

    ## This repo's mechanics

    Skills are Nix attrsets, rendered to SKILL.md for both Claude Code
    (`~/.claude/skills/`) and opencode (`~/.config/opencode/skills/`):
    - General skills: `modules/home/ai/shared/skill/<name>.nix`
    - Workflow skills: `modules/home/ai/shared/workflow/skill/<name>.nix` (also imported by opencode orchestrator agents)
    - Shared fragments (single source of truth, e.g. `teaConventions`): `modules/home/ai/shared/workflow/templates.nix` — interpolate, never copy.
    - Model-invoked: omit `"disable-model-invocation"`. User-invoked: set it `true`.
    - After editing: `nix fmt`, then rebuild home config to deploy.

    ## Invocation (skills only)

    Two choices, trading different costs:
    - A **model-invoked** skill keeps its description in the context window every turn, so the agent can fire it autonomously and other skills can reach it. It costs **context load**.
    - A **user-invoked** skill strips the description from the agent's reach; only you, typing its name, can invoke it. Zero context load, but it spends **cognitive load**: *you* are the index that must remember it exists.

    Pick model-invocation only when the agent must reach the skill on its own,
    or another skill must. When user-invoked skills multiply past what you can
    remember, the cure is a **router skill** that names the others and when to
    reach for each.

    ## Context pointers

    A **context pointer** is a reference held in the agent's context that names
    some out-of-context material and encodes the condition for reaching it. A
    skill's description is one; a line in `AGENTS.md` naming a doc is the same
    object. The pointer's *wording*, not its target, decides when the agent
    reaches the material — and how reliably. A must-have target behind a weakly
    worded pointer is a variance bug: sharpen the wording first, and inline the
    material only if sharpening fails.

    A pointer does two jobs — state what the material is, and list the
    **branches** that should trigger reaching it. Every word of an
    always-loaded pointer costs on every turn, so it earns even harder pruning
    than the body:
    - **Front-load the leading word** — the pointer is where it does its triggering work.
    - **One trigger per branch** — synonyms that rename a single branch are one branch written twice; collapse them.
    - **Cut identity the body already carries.**

    A user-invoked description is human-facing: a one-line summary, trigger
    lists stripped.

    ## Information hierarchy

    A document is built from two content types — **steps** (ordered actions)
    and **reference** (definitions, rules, facts consulted on demand) — placed
    on a ladder ranked by how immediately the agent needs the material:
    1. **In-file step** — the primary tier: what the agent does, in order.
    2. **In-file reference** — consulted on demand. Often a legitimately flat peer-set — a fine arrangement, not a smell.
    3. **Disclosed reference** — pushed into a separate file behind a **context pointer**, loaded only when the pointer fires.

    Push too little down and the top bloats; push too much and you hide
    material the agent actually needs. That tension is the whole decision.

    **Progressive disclosure** is the move down the ladder so the top stays
    legible. Branching is the cleanest disclosure test: inline what every
    branch needs; push behind a pointer what only some branches reach.

    **Co-location** is the within-file companion: where the ladder decides
    *how far down* a piece sits, co-location decides *what sits beside it*.
    Keep a concept's definition, rules, and caveats under one heading rather
    than scattered, so reading one part brings its neighbours with it.
    (Distinct from duplication: that repeats one meaning in two places;
    scattering fragments one meaning across many.)

    ## Steps and completion criteria

    Every step ends on a **completion criterion** — the condition that tells
    the agent the work is done. Two properties make it a lever:
    - **Clarity** — can the agent tell done from not-done? A vague bound ("understanding reached") invites **premature completion**: ending the step before it is genuinely done, pulled by the visible steps still ahead. Sharpen the bound first; only if it is irreducibly fuzzy *and* you observe the rush, hide the later steps by splitting the sequence across a real context boundary (a hand-off or subagent dispatch — an inline call clears nothing).
    - **Demand** — how much it requires. "Every modified model accounted for" forces thorough work where "produce a change list" does not. Demand drives **legwork** — digging latent in the wording rather than written as its own step — and it binds flat reference too: "every rule applied" is how an all-reference document still carries an exhaustiveness bar.

    The strongest criteria are both checkable and exhaustive.

    ## When to split

    Each cut spends one of the two loads, so split only when the cut earns it:
    - **By sequence** — split a run of steps where the post-completion steps tempt the agent to rush the one in front of it.
    - **By invocation** — split off a model-invoked skill when a distinct leading word should trigger it on its own. You pay context load for the new always-loaded description.

    ## Leading words

    A **leading word** is a compact concept already in the model's pretraining
    (*tight*, *red*, *tracer bullet*, *fog*) that the agent thinks with while
    running the document. Repeated as a token, never as a sentence, it anchors
    execution in the body and invocation in a pointer. Coining your own word
    recruits no priors — you pay in definition tokens what a pretrained word
    gives free; reach for an existing word first.

    Hunt restatements a single word retires: "fast, deterministic,
    low-overhead" → *tight*; "a loop you believe in" → *red* — a fuzzy gate
    becomes a binary observable state.

    **Negation** is the failure mode beside this lever: steering by prohibition
    drags the forbidden behaviour into context and makes it *more* available,
    not less — "don't think of an elephant" names the elephant. Prompt the
    **positive**: state the target behaviour so the banned one is never spoken.
    A prohibition earns its place only as a hard guardrail you cannot phrase
    positively; even then, pair it with the positive target.

    ## Pruning

    - **Single source of truth**: one authoritative place per meaning; changing behaviour is a one-place edit (in this repo: a `templates.nix` fragment). **Duplication** costs maintenance and tokens, and inflates a meaning's rank on the ladder.
    - **The environment is a source of truth too** — package scripts, config files, directory layout, `--help` output — and a document that restates it is a **cache**: a copy of a lookup, earning its load only when the lookup is expensive. Cache what the agent cannot find by looking: the unwritten convention, the reason behind a choice, the gotcha no config confesses. Leave one-command lookups to the environment, where they cannot go stale.
    - **Relevance**: does the line still bear on what the document does? Without pruning discipline the default fate is **sediment** — stale layers that settle because adding feels safe and removing feels risky.
    - **No-op test**, sentence by sentence: does this sentence change behaviour versus the default? The test is model-relative, not reader-relative — two people disagreeing about a no-op disagree about the default, and settle it by running the document, not by debate. When a sentence fails, delete the whole sentence rather than trim words from it. The test also grades leading words: a word too weak to beat the default (*be thorough*) is a no-op; the fix is a stronger word (*relentless*), not a different technique.
    - **Negative space**: every decision a document declines to make is delegated to the agent's priors rather than left neutral. Read a draft for its silences and decide each omission deliberately — fill it, or leave it open as a real branch.
  '';
}
