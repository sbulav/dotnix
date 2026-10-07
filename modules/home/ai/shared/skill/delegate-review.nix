let
  routing = (import ../routing.nix).policy;
in
{
  name = "delegate-review";
  version = "2.1.0";
  description = "Review PRs with independent model lenses, verify findings, and produce a fix plan. Use for PR review, review batches, or a second opinion on correctness, specification, or security.";
  "argument-hint" = "[PR number(s), or open]";
  "user-invocable" = true;
  allowed-tools = [
    "Bash"
    "Read"
    "Grep"
    "Glob"
    "Write"
    "TodoWrite"
    "Task"
  ];
  content = ''
    Review and plan fixes. A review request authorizes investigation; edits,
    posting a review, approval, and merge require corresponding user intent.
    If fixes were already requested, continue after review without asking again.

    For a local branch or work-in-progress review, use the requested scope
    instead of requiring a PR. Record HEAD and the resolved comparison base;
    include staged/unstaged changes when the user asks for current edits.
    Record untracked task files separately. Use the user's request or local
    spec as acceptance criteria. Skip PR-only metadata and recheck the working
    diff before finishing. A review must not create a PR just to obtain context.

    ## Prepare once per PR

    Resolve the repo/forge from remotes and the PR target. Fetch PR metadata,
    linked issue acceptance criteria, current review threads, and CI status
    with explicit repo flags. Record immutable base and head SHAs; compute
    the merge-base diff and give every reviewer those same revisions. Avoid
    changing the user's checked-out branch to review a PR.

    Build one brief containing PR URL, intent/AC, SHAs, change summary,
    relevant conventions, failing checks, unresolved threads, and hotspots.
    Inline a small diff; for large changes provide paths and commands to read
    full hunks plus surrounding code. Workers must inspect source, not just
    a summarizer's rendition. Partition large diffs by subsystem and ensure
    every behavior-changing area has an owner; parent checks cross-area effects.

    ## Choose review effort

    | Change | Lenses and default delegation |
    |---|---|
    | Small docs/mechanical change | parent review; one tier-1 lane only if independent checking helps |
    | Ordinary feature/fix | one cheap-lane correctness worker; parent spec and standards |
    | Complex behavior, concurrency, weak tests | two cheap lanes from distinct families: correctness and spec/architecture; parent synthesis |
    | Auth, secrets, injection, isolation | Astra/Opus 5.5 security lens plus an independent cheap-lane correctness lens |
    | Disputed serious finding | reproduce locally first; Sol/Sonnet 5.5 or stronger tie-break if still unresolved |

    Prefer a different model family from the author when a capable lane is
    available. Distinct prompts/lenses matter more than model count; two
    OpenAI tiers do not constitute family diversity. Record any loss of
    independence on fallback. Missing AC is a residual risk, not permission
    to invent requirements. Red CI adds a failure-analysis question.

    ${routing}

    ## Review lanes (2026-10-07)

    Fill each reviewer slot from the cheapest tier that has a reachable lane
    in a family other than the author's; descend a tier when the upper one
    is exhausted, rate-limited, already used for this PR's other lens, or
    the lens requires it (security, tie-break).

    1. Free: `hhdev-glm5-fp8/zai-org/GLM-5.3-Flash` via OpenCode (Zhipu,
       131k context, thinks by default). Default first reviewer for a diff
       that fits its window.
    2. Subscription, via `agy`: `gemini-3.1-pro-high` for spec/architecture
       and large diffs; `gemini-3.8-flash-high` for a fast correctness pass;
       `claude-opus-4-6-thinking` / `claude-sonnet-4-6` add independence only
       for a non-Claude author. `gpt-oss-120b-medium` gathers evidence only.
    3. Cheap metered: `hhdev-grok/grok-4.7` via OpenCode (xAI, 500k context,
       $0.20/$0.60 per Mtok) for the largest diffs or a third family.
    4. Metered strong: Sol/Sonnet 5.5, then Astra/Opus 5.5 — security lens,
       tie-breaks, and slots tiers 1-3 cannot fill.

    GLM, Gemini and Grok are three families distinct from both OpenAI and
    Anthropic, so cheap tiers usually satisfy the diversity rule on their own.
    Their findings are candidates: the parent verification below is what
    makes them safe to report. Record a tier 1-3 "no findings" on a risky
    area as thinner coverage in residual risks.

    Antigravity dispatch: run `agy models` once per run to confirm IDs.
    Headless agy writes files freely (`--mode plan` included) and auto-denies
    every shell command, ending the turn with an empty response. So give it
    a disposable detached worktree at the head SHA, and put the merge-base
    diff (`git diff base...head > .scratch/review-unique/diff.patch`) beside
    the brief; the brief says to use file reading and search only. From the
    worktree root (the agy workspace):

    ```bash
    agy --model gemini-3.1-pro-high --output-format json \
      --print-timeout 900s \
      -p "Read .scratch/review-unique/brief.md and complete only the assigned review."
    ```

    `-p` takes the prompt as its value, so it goes last. Effort is chosen by
    the model ID suffix (`-high`, `-medium`, `-low`). A `status` other than
    `SUCCESS`, an empty `response`, or a `denied_actions` entry is a failed
    review. Afterwards `git status` in that worktree must be clean apart
    from the scratch directory; then remove the worktree.

    ## Reviewer brief extension

    Role: read-only reviewer. No edits, commits, posting, approval, or merge.
    Supply the shared brief and exactly one primary lens:
    - Correctness: concrete bugs, edge cases, races, errors, missing coverage.
    - Spec: every acceptance criterion satisfied; missing or excess behavior.
    - Standards: documented repo conventions, module boundaries and seams.
      Consult `codebase-design` for interface changes. Smells such as duplicate
      logic, feature envy, shotgun surgery, and speculative abstractions are
      heuristics: flag only a concrete maintenance consequence in changed code.
      Repo conventions win; skip formatter/linter noise and taste-only advice.
    - Security: trust boundaries, authz, secret handling, injection, SSRF,
      path traversal and tenant isolation in reachable changed paths.

    Require a verdict, findings, and residual risks. Each finding includes
    severity, path:line at the recorded revision, a concrete trigger and
    impact, evidence/reproduction, and a fix direction. P0 blocks merge
    (security/data loss/broken behavior or AC); P1 should be fixed before
    merge; P2 is optional follow-up. State which files/checks were inspected.
    A verdict without source inspection is a failed review. Empty findings
    are valid; never manufacture issues to fill a quota.

    ## Reconcile and finish

    Check every claimed defect against source and runtime evidence. A model
    vote cannot establish truth. Ask once for missing evidence, then discard
    unsupported findings and disclose the coverage gap. Deduplicate common
    root causes while retaining source lenses. Explain dismissed serious
    claims and resolve disagreements through reproduction or a tie-break.

    Keep correctness, spec, standards and security outcomes visible as
    separate axes; success on one cannot cancel failure on another. Produce
    an overall verdict from the worst supported axis and an ordered fix plan
    with files and verification steps. Report untested assumptions, skipped
    areas, unavailable reviewers and CI blockers. Recheck PR head before
    finishing; if changed, review the new delta before claiming coverage.

    Final output: verdict, per-axis findings (or no findings), fix plan,
    residual risks, and compact routing/verification evidence. For a batch,
    finish one PR's synthesis before starting another wave; keep within the
    shared concurrency cap. Continue with fixes/posting only when already
    requested; otherwise deliver the review and stop.

    Input: $ARGUMENTS
  '';
}
