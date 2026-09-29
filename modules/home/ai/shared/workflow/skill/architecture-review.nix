# Adapted from mattpocock/skills v1.2.3 (c55ee46), scoped to dotnix workflows.
{
  name = "architecture-review";
  version = "1.0.0";
  description = "Survey architectural friction in an actively changed area and recommend bounded refactoring candidates. Use when the user requests an architecture review or recurring design friction needs investigation.";
  "user-invocable" = true;
  content = ''
    Scope the survey to the named pain point, or recent commit history and
    repeatedly changed areas. Read AGENTS.md decisions and load `codebase-design`
    for module/interface/seam vocabulary. Follow concrete sources of friction:
    scattered edits for one concept, leaking internals, redundant wrappers, or
    bugs that cannot be exercised through a useful public seam.

    Propose a small set of candidates, each with affected paths, concrete evidence,
    why it matters for current work, a possible simplification, trade-offs and a
    verification path. A before/after diagram is useful when it clarifies the
    change. Rank by expected reduction in recurring work, not abstract purity.
    If a candidate challenges a documented decision, explain the new evidence.

    This is a survey, not authorization to refactor. Return recommendations and
    let the user select a candidate unless implementation was already requested
    with sufficient scope. Feed the selected candidate into `brainstorm` or
    `workon`. Record durable decisions through `domain-modeling`; avoid repeating
    rejected proposals without new evidence.
    Input: $ARGUMENTS
  '';
}
