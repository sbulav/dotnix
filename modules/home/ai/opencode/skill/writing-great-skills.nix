# Adapted from mattpocock/skills `writing-great-skills` — the reference to
# consult when authoring or editing skills in this repo.
{
  name = "writing-great-skills";
  version = "1.0.0";
  description = "Reference for writing and editing skills well — the vocabulary and principles that make a skill predictable. Invoke when authoring or changing any skill.";
  "disable-model-invocation" = true;
  allowed-tools = [
    "Read"
    "Grep"
    "Glob"
  ];
  content = ''
    A skill exists to wrangle determinism out of a stochastic system. **Predictability** — the agent taking the same *process* every run, not producing the same output — is the root virtue; every lever below serves it.

    ## This repo's mechanics

    Skills are Nix attrsets, rendered to SKILL.md for both Claude Code (`~/.claude/skills/`) and opencode (`~/.config/opencode/skills/`):
    - General skills: `modules/home/ai/opencode/skill/<name>.nix`
    - Workflow skills: `modules/home/ai/shared/workflow/skill/<name>.nix` (these are also imported by opencode orchestrator agents)
    - Shared fragments (single source of truth, e.g. `teaConventions`): `modules/home/ai/shared/workflow/templates.nix` — interpolate, never copy.
    - Model-invoked: omit `"disable-model-invocation"`. User-invoked: set it `true`.
    - After editing: `nix fmt`, then rebuild home config to deploy.

    ## Invocation

    Two choices, trading different costs:
    - A **model-invoked** skill keeps its description in the context window every turn, so the agent can fire it autonomously and other skills can reach it. It costs **context load**.
    - A **user-invoked** skill strips the description from the agent's reach; only you, typing its name, can invoke it. Zero context load, but it spends **cognitive load**: *you* are the index that must remember it exists.

    Pick model-invocation only when the agent must reach the skill on its own, or another skill must. When user-invoked skills multiply past what you can remember, the cure is a **router skill** that names the others and when to reach for each.

    ## Writing the description

    A model-invoked description does two jobs — state what the skill is, and list the **branches** that should trigger it. Every word increases context load:
    - Front-load the skill's leading word.
    - One trigger per branch — synonyms that rename a single branch are duplication; collapse them.
    - Cut identity that's already in the body; keep the description to triggers.

    A user-invoked description is human-facing: a one-line summary, trigger lists stripped.

    ## Information hierarchy

    A skill mixes two content types — **steps** (ordered actions) and **reference** (rules and facts consulted on demand) — placed on a ladder ranked by how immediately the agent needs the material:
    1. **In-skill step** — each ends on a **completion criterion**: checkable (agent can tell done from not-done) and, where it matters, exhaustive. A vague criterion invites premature completion.
    2. **In-skill reference** — a flat peer-set of rules is a fine arrangement, not a smell.
    3. **External reference** — pushed into a separate file behind a **context pointer**, loaded only when the pointer fires. The pointer's *wording* decides whether the agent reaches it.

    **Progressive disclosure** is the move down the ladder so the top stays legible. Branching is the cleanest disclosure test: inline what every branch needs; push behind a pointer what only some branches reach.

    ## When to split

    Each cut spends one of the two loads, so split only when the cut earns it:
    - **By invocation** — split off a model-invoked skill when a distinct leading word should trigger it on its own. You pay context load for the new always-loaded description.
    - **By sequence** — split a run of steps when the steps still ahead tempt the agent to rush the one in front of it.

    ## Pruning

    - **Single source of truth**: one authoritative place per meaning; changing behaviour is a one-place edit (in this repo: a `templates.nix` fragment).
    - **Relevance**: does the line still bear on what the skill does?
    - **No-op test**, sentence by sentence: does this sentence change behaviour versus the default? When one fails, delete the sentence rather than trim words from it. Be aggressive.

    ## Leading words

    A **leading word** is a compact concept already in the model's pretraining (*tight*, *red*, *tracer bullet*, *fog*) that the agent thinks with while running the skill. It anchors execution in the body and invocation in the description. Hunt restatements a single word retires: "fast, deterministic, low-overhead" → *tight*; "a loop you believe in" → *red*.

    ## Failure modes

    Diagnose a misbehaving skill against these:
    - **Premature completion** — ending a step before it's genuinely done. Sharpen the completion criterion first; split the sequence only if the criterion is irreducibly fuzzy and you observe the rush.
    - **Duplication** — the same meaning in more than one place. Costs maintenance and tokens, and inflates the meaning's rank.
    - **Sediment** — stale layers that settle because adding feels safe and removing feels risky. The default fate of any skill without pruning discipline.
    - **Sprawl** — too long even when every line is live. Cure with the ladder: disclose reference, split by branch or sequence.
    - **No-op** — a line the model already obeys by default; you pay load to say nothing. Fix a weak leading word with a stronger one (*relentless*, not *be thorough*).
    - **Negation** — steering by prohibition backfires: "don't think of an elephant" names the elephant. State the target behaviour so the banned one is never spoken; keep a prohibition only as a hard guardrail you can't phrase positively, and pair it with what to do instead.
  '';
}
