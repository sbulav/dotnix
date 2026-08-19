# Adapted from mattpocock/skills `grill-me` / `grilling` (v1.2.2) — the
# frontier/rounds interview loop, kept as a single user-invoked skill.
{
  name = "grill-me";
  version = "2.2.0";
  description = "Grill the user relentlessly about a plan, decision, or idea until every branch of the design tree is resolved. Use when the user wants to stress-test their thinking, uses any 'grill' trigger phrases, or when mid-task you hit an under-specified decision only the user can own — interview instead of guessing. Requires the user present: never self-invoke in an AFK or delegated worker session.";
  "argument-hint" = "[topic]";
  "user-invocable" = true;
  allowed-tools = [
    "Read"
    "Grep"
    "Glob"
    "Bash"
    "Task"
    "Skill"
  ];
  content = ''
    Interview the user relentlessly until you reach a shared understanding. Map
    this as a **design tree**: every decision branches into the decisions that
    hang off it.

    Work the tree in **rounds**. The **frontier** is every decision whose
    prerequisites are already settled — the questions you can ask *now* without
    guessing at answers you haven't heard yet. Ask the whole frontier in one
    round: number each question and give your recommended answer. Then wait for
    the user's answers before the next round.

    Each question should be formatted like so:

    ```
    ❓ **Q1** - **<question title>**: <question body, might be multiple paragraphs, including multiple choices>

    ➡️ <your recommended answer>
    ```

    Each round the user answers reshapes the tree — settled decisions push the
    frontier outward and unblock questions that depended on them. Recompute the
    frontier and ask the next round. A question whose answer depends on another
    question still open in this round belongs to a *later* round, not this one.

    Finding *facts* is your job, never the user's. When a frontier question
    needs a fact from the environment (filesystem, git history, config, docs),
    dispatch a sub-agent to find it — don't ask the user for anything you could
    look up yourself. Don't block on it: a running exploration is an unsettled
    prerequisite, so only the questions downstream of it wait for the sub-agent
    to report — ask the rest of the frontier now. The *decisions* are the
    user's — put each to them and wait.

    Be direct and skeptical, never sycophantic. Push back when an answer is
    vague, contradictory, or under-specified.

    When the grilling touches domain terms that are ambiguous or whose code
    name clashes with the business name, call the Skill tool with
    `domain-modeling` and fold its definition questions into the frontier.

    The session is done when the frontier is empty: every branch of the design
    tree visited, nothing left silently assumed. Then produce a
    **shared-understanding summary**: the resolved decisions, the agreed scope,
    and the open risks deferred by choice. Do not act on it until the user
    confirms you have reached a shared understanding.

    ## Input

    Topic to grill on (may be empty when self-invoked mid-task — then grill
    the under-specified decision that triggered this skill, scoped to that
    decision's subtree, not the whole plan):
    $ARGUMENTS
  '';
}
