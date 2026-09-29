let
  routing = (import ../routing.nix).policy;
in
{
  name = "delegate-review";
  version = "2.0.0";
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
    | Small docs/mechanical change | parent review; one worker only if independent checking helps |
    | Ordinary feature/fix | one Sol/Sonnet correctness worker; parent spec and standards |
    | Complex behavior, concurrency, weak tests | two distinct workers: correctness and spec/architecture; parent synthesis |
    | Auth, secrets, injection, isolation | Astra/Opus security lens plus independent correctness lens |
    | Disputed serious finding | reproduce locally first; one stronger independent tie-break if still unresolved |

    Prefer a different model family from the author when a capable lane is
    available. Distinct prompts/lenses matter more than model count; two
    OpenAI tiers do not constitute family diversity. Record any loss of
    independence on fallback. Missing AC is a residual risk, not permission
    to invent requirements. Red CI adds a failure-analysis question.

    ${routing}

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
