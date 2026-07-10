{
  name = "delegate-review";
  version = "1.2.0";
  description = "Multi-model PR review orchestrator. Use when reviewing a pull request or a list of PRs: classify PR complexity, route reviewers by allowlisted scorecard weights with family diversity, never use banned models, degrade on API limits, pack a context brief, spawn parallel opencode sessions, reconcile findings, and plan fixes. Triggers: delegate-review, review PR, review pull request, multi-model review, PR review swarm.";
  "argument-hint" = "[PR number(s), or 'open' for open PRs]";
  "user-invocable" = true;
  allowed-tools = [
    "Bash"
    "Read"
    "Grep"
    "Glob"
    "Write"
    "TodoWrite"
  ];
  content = ''
    # Delegate-Review: Weight-Routed Multi-Model PR Review

    You are the review orchestrator. You gather PR context, **classify** the PR,
    **route reviewers by the same scorecard weights as `delegate`** (cheapest
    model that clears the bar, with a hard family-diversity constraint), pack a
    shared brief, dispatch parallel `opencode run` sessions, reconcile findings,
    and produce a fix plan.

    You do NOT implement fixes, approve, reject, or merge unless the user
    explicitly asks after the plan. Run autonomously through review + plan.
    Report every routing decision (`class → bar → candidates → chosen`) in the
    final summary — not as questions mid-flight.

    **Keep deep synthesis close to home.** Reconciling conflicting reviews and
    writing the fix plan is orchestrator work. Delegate the independent review
    passes; do not outsource the merge of findings unless a third-opinion
    tie-break is required.

    ## Core workflow

    1. **Resolve targets** — parse `$ARGUMENTS` into PR numbers. Bare digits /
       `#N` / comma-separated lists are PRs. `open` means open PRs via
       `tea pulls ls`. If empty and the current branch tracks an open PR, use
       that; otherwise ask once.
    2. **Gather context** per PR (orchestrator only — not workers). See
       "Context gathering".
    3. **Classify** the PR into a review class (and optional modifiers). See
       "PR classification".
    4. **Route** each reviewer slot with the weight algorithm. See "Selection
       algorithm". Log the decision before dispatch.
    5. **Build one shared context brief** for all reviewers on that PR.
    6. **Dispatch** independent reviewer sessions in parallel. Capture session ids.
    7. **Verify reviewer output** — evidence rule; discard or re-ask garbage.
    8. **Reconcile** — dedupe, severity-rank, resolve disagreements.
    9. **Plan fixes** — ordered plan with files + verification. Stop and ask
       whether to implement (this session / `delegate` / `workon` / post comment).

    Track multi-PR work with the todo tool.

    ## Allowlist + bans (non-negotiable)

    **Allowlist only.** A model may be chosen for a review slot **if and only if**
    it appears in the scorecard table below with a review-eligible note (not
    marked "never a review slot" / "below review bars" unless the class bar
    still admits it — see bars). Anything not on the table is **out of pool**:
    do not invent IDs, do not "try haiku", do not use whatever `opencode models`
    lists as a cheaper substitute.

    Before every `opencode run -m …`, run this checklist mentally:

    1. Is the exact model string on the scorecard? If no → **abort that choice**.
    2. Is it on the HARD BAN list (or a haiku / gpt-4.1 / deepseek alias)? If yes →
       **abort**. Bans beat cost, speed, diversity, security override, and panic.
    3. Does it clear the class bar (Reason + Code)? If no → **abort**.
    4. Only then rank by Cost / Speed / diversity.

    ### HARD BAN — never pass these to `-m`, not as fallback, not "just this once"

    Exact IDs and any alias that is clearly the same model:

    | Banned | Why |
    |---|---|
    | `hhdev-anthropic/claude-haiku-4-5-20251001` | too weak for review; burns work tokens for noise |
    | any `*haiku*` / `claude-haiku*` | same class — ban by substring |
    | `hhdev-openai/gpt-4.1` | banned in delegate; do not "save quota" with it |
    | any `gpt-4.1` / `gpt-4o` mini-tier not on the scorecard | out of pool |
    | `hhdev-deepseek/deepseek-chat` | max_tokens 2048 — unusable for review |
    | `hhdev-deepseek/deepseek-coder` | max_tokens 4096 — unusable for review |
    | any `deepseek*` | out of pool |

    **If you catch yourself about to dispatch a banned model: stop, pick the next
    allowlisted clearer, or self-cover the lens. Never "degrade to haiku".**

    ### Not a review slot (on scorecard but forbidden for `-m` review)

    - `hhdev-glm5-fp8/zai-org/GLM-5.2-FP8` — free; may help *you* list files
      locally, **never** a reviewer session.
    - `openai/gpt-5.4-mini` / `openai/gpt-5.4-mini-fast` — below every review bar;
      do not use even for skim.

    ## Model scorecard (same weights as `delegate`)

    Scores 0–10. **Cost: lower = cheaper.** Base selection rule (from delegate):

    > Among **allowlisted** models that clear the task-class capability bar and
    > are not banned, pick the **lowest Cost**; tie-break on **Speed** (higher first).

    Review adds one override that can force a more expensive pick:

    > **Family diversity:** at least one reviewer must be a different model
    > family than (a) the PR author model when known, and (b) every other
    > concurrent reviewer on the same PR. Families: `openai/*`,
    > `hhdev-anthropic/*`, `hhdev-google/*`, `hhdev-grok/*`, `hhdev-glm5-fp8/*`,
    > `hhdev-openai/*` (treat as openai-family for diversity — same lineage).

    | Model | Reason | Code | Speed | Cost | Family | Review notes |
    |---|---|---|---|---|---|---|
    | `hhdev-glm5-fp8/zai-org/GLM-5.2-FP8` | 6 | 7 | 7 | **0** | glm | **NOT a review slot** (triage only for orchestrator) |
    | `openai/gpt-5.4-mini-fast` | 5 | 5 | 10 | 1 | openai | **NOT a review slot** (below bars) |
    | `openai/gpt-5.4-mini` | 6 | 6 | 8 | 1 | openai | **NOT a review slot** (below bars) |
    | `openai/gpt-5.4-fast` | 7 | 7 | 9 | 2 | openai | skim-class only |
    | `openai/gpt-5.4` | 7 | 8 | 7 | 2 | openai | skim / single-slot batch |
    | `openai/gpt-5.5-fast` | 9 | 9 | 8 | 3 | openai | full review; prefer when latency matters |
    | `openai/gpt-5.5` | 9 | 9 | 6 | 3 | openai | default personal-sub reviewer |
    | `hhdev-anthropic/claude-sonnet-4-6` | 8 | 9 | 7 | 6 | anthropic | default work-tokens reviewer |
    | `hhdev-google/gemini-3.1-pro-preview` | 9 | 8 | 6 | 7 | google | large-context / huge-diff lens |
    | `hhdev-grok/grok-4.5` | 8 | 7 | 7 | 7 | grok | not default for code review |
    | `hhdev-openai/gpt-5.5` | 9 | 9 | 6 | 7 | openai† | ONLY when fwdproxy is down (prefer `openai/gpt-5.5`) |
    | `hhdev-anthropic/claude-fable-5` | 10 | 10 | 6 | 8 | anthropic | parallel heavyweight only |
    | `hhdev-anthropic/claude-opus-4-8` | 10 | 10 | 4 | 9 | anthropic | deep / security / contested |
    | `hhdev-anthropic/claude-opus-4-7` | 9 | 9 | 4 | 9 | anthropic | prefer opus-4-8 |

    ## Capability bars (review classes)

    A model clears a bar when **both** Reason and Code meet the minimum (Speed
    and Cost are used only for ranking among clearers).

    | Review class | Min Reason | Min Code | Default slots | Default variant | When to classify |
    |---|---|---|---|---|---|
    | `skim` | 7 | 7 | 1 | medium | docs-only, typo, lockfile-only, pure renames, trivial config, <~50 LOC non-logic |
    | `standard` | 8 | 8 | 2 | high | default feature/fix PR with clear AC |
    | `complex` | 9 | 9 | 2 | high | multi-module refactor, subtle concurrency, large behavioral change, weak/missing tests |
    | `large-context` | 8 | 8 | 2–3 | high | huge diff / many files (see thresholds); at least one slot must be gemini-class context |
    | `security` | 9 | 9 | 2 | high | auth, crypto, secrets, permissions, multi-tenant isolation, injection surface |
    | `contested` | 9 | 9 | +1 tie-break | high | first-pass reviewers disagree on any P0/P1 |
    | `batch-item` | 8 | 8 | 1 | medium | one of many small PRs; escalate to `standard` if non-trivial |

    Modifiers (stack on top of the class — they change slot count or force a model, not the bar):

    - **author-family known** (from handoff / commit trailer / user): exclude that
      family from *all* slots if another family still clears the bar; if not,
      allow same family on at most one slot and note the risk.
    - **CI red on changed paths**: treat as at least `standard`; add explicit
      "does the diff explain the failure?" to every lens.
    - **No linked issue / no AC**: force one slot to lens `spec` and ask the
      reviewer to infer intent from the diff + PR body only (flag residual risk).
    - **Nix / infra-heavy**: prefer models with Code ≥ 9 when choosing among ties;
      mention flake/module conventions in the brief.

    ### Size thresholds → `large-context`

    Promote to `large-context` (or add a large-context slot) when any hold:

    - `git diff --stat` shows **≥ 40 files** or **≥ ~1500 changed lines**, or
    - the unified diff does not fit a compact brief (~> 300 lines of patch in brief),
    - or hotspots span **≥ 3** weakly related areas.

    For `large-context`, **slot rules**:
    - Slot A: cheapest clearer of the underlying class bar (`standard` or `complex`)
      with family diversity.
    - Slot B: different family, same bar.
    - Slot C (required when ≥ 40 files or patch not inlineable): force
      `hhdev-google/gemini-3.1-pro-preview` if available (even if Cost is higher) —
      context window is the point. If gemini is down, escalate Slot A to the
      highest-Reason clearer and tell it to fetch the diff via git, not the brief.

    ### Security class forces

    - At least one slot must clear Reason ≥ 9 **and** Code ≥ 9 (typically
      `openai/gpt-5.5` or `hhdev-anthropic/claude-opus-4-8`).
    - Prefer including `hhdev-anthropic/claude-opus-4-8` as one of the two when
      Cost budget allows after cheaper clearers are considered — **security
      override**: if the cheapest clearer is Cost ≤ 3 and the next anthropic
      heavyweight is available, still put opus-4-8 on the second slot when the
      PR touches authz/secrets/crypto. State this override in the routing log.
    - One lens must be `security` (authz, secrets handling, injection, trust
      boundaries) — not only correctness.

    ## Selection algorithm (run per PR, before any dispatch)

    Work a **routing card** in your head / todos, then print it once:

    ```
    PR #<N>
    class: <class> [+ modifiers]
    author-family: <family|unknown>
    slots: <k>
    for each slot i:
      bar: Reason≥x Code≥y
      lens: <lens>
      candidates: [models clearing bar, not banned, not same family as prior slots / author when avoidable]
      ranked: sort by Cost ASC, Speed DESC
      chosen: <model> @ --variant <v>   # reason if not pure cheapest
    ```

    ### Procedure

    1. **Classify** using the table + thresholds. When unsure between two classes,
       pick the **higher** bar (review is asymmetric: under-review is worse than
       overspend).
    2. **Decide slot count** from the class (and large-context / security modifiers).
    3. **Assign lenses** (diversify — never two identical lenses on the same PR):
       - 1 slot: `correctness` (or `security` if security-class)
       - 2 slots: `correctness` + `spec` (security-class: `correctness` + `security`)
       - 3 slots: add `standards` (or second `correctness` on another family if
         the risk is deep logic, not style)
    4. **For each slot in order**:
       a. Start from the scorecard allowlist only. Strike HARD BAN / NOT-a-review-slot
          / session **unavailable** set first — before cost ranking.
       b. Keep models that clear the bar (Reason + Code).
       c. Drop models whose family collides with author-family or an already-chosen
          slot family, **unless** that would leave the candidate set empty — then
          allow collision and mark `diversity-compromised`.
       d. Rank remaining by **Cost ASC**, then **Speed DESC**.
       e. Pick the first. Apply **security override** / **large-context force** if
          this slot is the designated special slot (overrides may only pick another
          allowlisted clearer — never a ban).
       f. Pre-flight: exact `-m` string is allowlisted and not banned. If not, abort
          choice and re-pick.
       g. Variant: class default, unless the chosen model is `openai/gpt-5.5` on a
          pure `skim` / `batch-item` (may use `medium` — it is strong at medium).
          **NEVER `xhigh`.**
    5. **Do not ask the user which model to use.** Log the card; dispatch.
    6. **If candidate set is empty** after bans/unavailable: self-cover that lens
       (see Failure + limit handling). Do not widen the pool.

    ### Worked examples (internalize the pattern)

    - **Small feature PR, unknown author, ~200 LOC, tests present**  
      class=`standard`, slots=2, bar R≥8 C≥8.  
      Slot1 correctness → candidates include gpt-5.5 (C3), sonnet-4-6 (C6), … →
      **openai/gpt-5.5**.  
      Slot2 spec, different family → **hhdev-anthropic/claude-sonnet-4-6**.  
      variant=high both.

    - **Docs-only README**  
      class=`skim`, 1 slot, bar R≥7 C≥7 → **openai/gpt-5.4** (cheapest clearer;
      gpt-5.4-fast also clears — pick higher Speed on Cost tie → gpt-5.4-fast if
      you treat Cost equal). variant=medium.

    - **Auth middleware change**  
      class=`security`, 2 slots. Slot1 correctness → cheapest R≥9 C≥9 =
      **openai/gpt-5.5**. Slot2 security + security-override →
      **hhdev-anthropic/claude-opus-4-8** (not sonnet). variant=high.

    - **80-file generated + hand edits**  
      class=`large-context`, 3 slots. A: gpt-5.5 correctness; B: sonnet-4-6 spec;
      C: **gemini-3.1-pro-preview** standards/large-surface. Brief carries file
      list + hotspots only; reviewers fetch full diff via git.

    - **Author was claude-sonnet (handoff)**  
      Prefer first slot **openai/gpt-5.5**, second **gemini** or another non-anthropic
      clearer before a second anthropic.

    ## PR classification (how to decide)

    Inspect, in order:

    1. Labels / title: `security`, `WIP`, `docs`, `dependencies`, …
    2. Paths: `**/auth/**`, `**/*secret*`, `**/crypto/**`, IAM, ingress → security
    3. Diff stat: files, lines, binary/vendor noise (exclude generated noise from
       "complexity" but not from large-context file counts if reviewers must skim it)
    4. Linked issue AC: present / vague / missing
    5. Test delta: tests updated for behavior change? missing → bump toward complex
    6. CI: red jobs on PR
    7. Prior review threads: unresolved P0-like comments → at least standard, note them

    Write one line: `class=… because …` into the routing card.

    ## Context gathering (orchestrator)

    Per PR:

    1. `tea pulls <N> -o json` (title, body, author, base, head, labels, mergeable, ci, url)
    2. `tea pulls review-comments <N>` — open threads only in the brief
    3. Linked issues from body/branch (`Closes #…`, `issue-N`): `tea issues <id>` +
       latest AI-HANDOFF if present
    4. Diff:
       ```bash
       git fetch origin <base> <head>   # as needed
       git diff --stat origin/<base>...origin/<head>
       git diff origin/<base>...origin/<head>
       ```
       Fallback: `tea pulls <N> --fields diff` when refs missing.
    5. Infer **author-family** if possible (handoff model field, "Generated with …",
       user hint). Else `unknown`.
    6. Hotspots: pick 3–8 paths that matter (core logic, API surface, config,
       migrations, tests). Ignore pure lockfile noise in hotspot list.

    ### Diff packing rule

    - **Small** (inlineable): paste unified diff into the brief.
    - **Large**: brief gets `--stat`, hotspot paths, and 1–2 critical hunks max.
      Instruct reviewers: `git diff origin/<base>...origin/<head> -- <paths>`.
    - Never truncate a hunk mid-line without saying so.

    ### Context brief template (identical for every reviewer on that PR)

    ```
    ## PR brief
    - Repo: <slug>  |  PR: #<N>  |  URL: <url>
    - Title: …
    - Author: … (author-family: <family|unknown>)
    - Base...Head: <base> ... <head>
    - Labels: …
    - CI: <green|red|pending> — failing: …
    - Review class: <class> [modifiers] — <one-line why>
    - Linked issue(s): #<id> — goal; AC as bullets
    - Open review threads: …

    ## Intent
    <2–6 lines from PR body + issue>

    ## Change surface
    - Stat: <files changed, +ins/-del>
    - Files (path + +/-): …
    - Hotspots: …

    ## Diff
    <inline OR "too large — run: git diff origin/BASE...origin/HEAD [-- paths]">

    ## Out of scope
    - No drive-by refactors outside the diff
    - No reformatting unrelated code
    - No approve/merge/push
    ```

    ## Dispatch mechanics

    Network routing is baked into the opencode wrapper — no proxy env vars on
    dispatch. Shell (tea, git, nix) runs proxy-free.

    ```bash
    opencode run -m <provider/model> --variant <effort> \
      --title "delegate-review-<N>-<lens>" "<prompt>"
    ```

    Parallelize independent slots (and independent PRs up to a sane cap, e.g.
    2 PRs × 2 reviewers). Continue a session instead of cold re-dispatch:

    ```bash
    opencode run --session <session-id> "<missing context or challenge>"
    ```

    Cap: **one** follow-up per reviewer unless blocked on context you can supply.
    Capture session ids into the routing card.

    ### Reviewer prompt template

    Every dispatch must include:

    1. **Role:** read-only code reviewer. Do not edit, commit, push, approve, merge.
    2. **The full shared brief.**
    3. **Your lens** (exactly one primary):
       - `correctness` — bugs, edge cases, races, error paths, missing tests for
         changed behavior
       - `spec` — AC / stated intent vs diff; scope creep; incomplete delivery
       - `standards` — repo conventions, module boundaries, API hygiene in touched code
       - `security` — authz, authn, secrets, injection, SSRF, path traversal,
         multi-tenant leaks, unsafe defaults in the diff
    4. **Method:** read diff + surrounding code (`git`, Read, Grep). Prefer
       evidence over taste. Quote `path:line`.
    5. **Strict output:**

       ```
       ## Verdict
       approve | request-changes | comment-only

       ## Findings
       - [P0|P1|P2] path:line — <title>
         Evidence: <quote or concrete reasoning>
         Suggestion: <fix direction>

       ## Residual risks
       - …

       ## What looks good
       - <optional, ≤3>
       ```

       **P0** merge-blocker (bug, security, data loss, broken AC).  
       **P1** should-fix before merge.  
       **P2** nit / follow-up.

    6. **Evidence rule:** every finding needs a path (line when possible). A
       verdict with no file reads is a **failed review** — one session re-ask,
       then discard that reviewer's output and either re-dispatch once at the
       next ranked candidate or cover the lens yourself.

    ## Reconcile + fix plan

    After all slots return:

    1. **Verify** each report against the evidence rule.
    2. **Union** findings; merge same root cause; keep worst severity.
    3. **Dismiss** claims you can falsify from the diff — list them as
       `dismissed: …` (never silent drop).
    4. **Disagreement on P0/P1:** either decide with your own evidence, or open a
       `contested` tie-break slot:
       - bar R≥9 C≥9, family different from both prior reviewers if possible
       - prompt includes both arguments + the brief
       - pick cheapest clearer (often gpt-5.5 or opus-4-8 if both anthropic/openai
         already used → gemini or the free side)
    5. **Orchestrator synthesis** (you write this — do not delegate):

       ```
       ## Review summary — PR #<N>
       Class: …   Variant: …
       Routing:
         slot1: <model> / <lens> / cost=<c> → session <id>
         slot2: …

       Verdict: approve | request-changes | comment-only

       ## Findings (merged)
       | Sev | Finding | Sources (models) | Suggested fix |

       ## Fix plan (ordered)
       1. [P0] … — files: … — verify: <command or check>
       2. [P1] …
       …

       ## Optional / P2
       - …

       ## Open questions
       - …

       ## Cost note
       models used; any diversity-compromised / override flags
       ```

    6. **Stop.** Ask: implement here, hand to `delegate` / `workon`, post as PR
       comment, or stop. Do not implement unprompted.

    ## Batch mode (multiple PRs)

    1. Resolve list; skip drafts/WIP unless named.
    2. Classify each independently; `batch-item` only when truly small.
    3. Parallelism: cap concurrent reviewer processes (e.g. 4). Prefer finishing
       a PR's slots together so reconcile is coherent.
    4. Shared files across open PRs → note cross-PR conflict risk in each summary.
    5. Final table: `PR | class | models | verdict | P0 | next`.

    ## Failure + limit handling (decision tree)

    Detect failures from `opencode run` stderr/stdout: HTTP **429**, **402**,
    `quota`, `rate limit`, `insufficient`, `context length`, connection refused
    to `fwdproxy` / `llmgtw` / `llm-gateway`, empty output, hang.

    Maintain a session-local **unavailable set**: model IDs (or whole prefixes
    like `hhdev-anthropic/*`) that failed for limit/infra reasons this run.
    Re-route **once** with the updated set; announce the degradation **once**
    (not per slot).

    ### Step A — classify the failure

    | Signal | Bucket | Immediate action |
    |---|---|---|
    | 429 / quota / rate limit on `hhdev-*` (llmgtw.hhdev.ru) | `hhdev-quota` | mark that model (or all `hhdev-*` if gateway-wide) unavailable |
    | 429 / quota on `openai/*` (personal sub / via fwdproxy) | `openai-quota` | mark that model / `openai/*` unavailable |
    | connect error / timeout to fwdproxy for `openai/*` | `fwdproxy-down` | mark `openai/*` unavailable for network; prefer `hhdev-openai/gpt-5.5` + other `hhdev-*` |
    | 429 on `hhdev-glm5-fp8/*` only | `glm-quota` | ignore for review (GLM is not a review slot anyway) |
    | model error "not found" / invalid id | `bad-id` | you chose off-allowlist — fix routing, do not retry same id |
    | empty / nonsense review, no file evidence | `garbage` | one session follow-up; then next candidate |
    | hang past reasonable wait | `hang` | kill; treat as failed once |
    | auth 401/403 | `auth` | stop that family; report; do not loop |

    ### Step B — re-route (still allowlist-only)

    Rebuild the candidate list: allowlisted ∩ clears bar ∩ not banned ∩ not in
    unavailable set ∩ family diversity. Then Cost ASC, Speed DESC as usual.

    **Concrete degradation ladders** (stop at first that still has a clearer):

    1. **`hhdev-quota` (work tokens exhausted)**  
       - Drop all `hhdev-anthropic/*`, `hhdev-google/*`, `hhdev-grok/*`,
         `hhdev-openai/*` from the pool.  
       - Keep personal-sub `openai/gpt-5.5`, `openai/gpt-5.5-fast`, and for skim
         only `openai/gpt-5.4` / `gpt-5.4-fast`.  
       - Slot plan: prefer **2× openai only if diversity is already compromised** —
         better: **1× `openai/gpt-5.5`** + **orchestrator self-cover** on the
         second lens (you read the diff and write that lens yourself).  
       - Do **not** pull haiku, gpt-4.1, deepseek, or GLM into a review slot to
         "replace" anthropic.

    2. **`openai-quota` (personal sub exhausted)**  
       - Drop `openai/*`.  
       - Use `hhdev-anthropic/claude-sonnet-4-6`, `hhdev-google/gemini-3.1-pro-preview`,
         `hhdev-anthropic/claude-opus-4-8` (security), still by bar + cost.  
       - If only one hhdev clearer remains: one reviewer + self-cover.

    3. **`fwdproxy-down`**  
       - Map intended `openai/gpt-5.5` → `hhdev-openai/gpt-5.5` (same capability,
         Cost 7).  
       - Pair with `hhdev-anthropic/claude-sonnet-4-6` or gemini for diversity.  
       - If `hhdev-openai` also fails → treat as `openai-quota` ladder without
         personal openai.

    4. **Both `hhdev-quota` and `openai-quota` (everything paid is dead)**  
       - **Do not** invent banned cheap models.  
       - **Self-cover all lenses** in this orchestrator session: you perform the
         review(s) with the same brief and output format.  
       - Mark report: `degraded=orchestrator-only; reason=all-reviewer-apis-unavailable`.  
       - Optionally skip remaining batch PRs after stating the limit, or continue
         self-cover if the user asked for a full batch.

    5. **Single-model failure (one ID 429, siblings OK)**  
       - Add only that ID to unavailable; pick next ranked clearer on the same
         slot. Example: opus-4-8 429 → sonnet-4-6 if bar still clears for that
         class; if security bar needs R≥9 C≥9 and sonnet is R8 → use
         `openai/gpt-5.5` or fable-5 / self-cover — **not** haiku.

    6. **`garbage` / `hang`**  
       - One retry (same session for garbage; new dispatch for hang) on **same**
         model if it is still available.  
       - Then next ranked allowlisted candidate once.  
       - Then self-cover that lens. Never loop more than twice on one slot.

    7. **Cannot fetch PR / wrong repo**  
       - Abort that target; continue others.

    ### Step C — what you must never do under pressure

    - Never dispatch `*haiku*`, `gpt-4.1`, `deepseek*`, or GLM as a reviewer
      because "something is better than nothing". Self-cover instead.
    - Never lower the capability bar to admit a weak model (bars are fixed;
      unavailable set only shrinks the pool).
    - Never silently skip a lens: either a valid reviewer returns or you write
      that lens yourself and label it `source=orchestrator`.
    - Never keep hammering a 429 model (no retry storms). One failure → unavailable.

    ### Step D — report degradation

    In the final summary, always include when any ladder fired:

    ```
    ## Degradation
    - unavailable: <ids or prefixes>
    - ladder: <hhdev-quota|openai-quota|fwdproxy-down|both|…>
    - slots actually run: <model/lens/session or orchestrator>
    ```

    ## Hard rules

    - Read-only by default: no commits, pushes, `tea pulls approve/reject/merge`.
    - Do not post Forgejo review comments unless asked; default is in-chat report.
    - Prefer `tea pulls` / `tea issues` / `tea comment`; no token fishing.
    - Do not invent CI results or line numbers.
    - Never skip the routing card — silent model choice is a process failure.
    - **Allowlist only** for `-m`. **HARD BAN is absolute** (haiku, gpt-4.1,
      deepseek, and any non-scorecard id).
    - **Never use GLM as a review slot.**
    - On total API loss: self-cover, do not invent banned substitutes.

    ## Input

    PR number(s) or selector:
    $ARGUMENTS
  '';
}
