# Shared policy, interpolated into both delegation skills. Model roles are
# workload defaults, not benchmark scores or guarantees of gateway access.
{
  policy = ''
    ## Routing and effort (2026-09-29)

    Choose by task risk, available tools, quota, and total time to a verified
    result. Subscription calls consume quota; self-hosted calls consume time.
    Use a shell command for deterministic extraction or formatting. Keep a
    small task local when briefing and reviewing a worker would take longer.
    Delegate a bounded independent task when the parent can make progress
    alongside it, or an independent review would materially reduce risk.

    | Work | Preferred lane | Escalation / alternative |
    |---|---|---|
    | Bulk extraction, summaries, text drafts | self-hosted Gemma | GPT-6 Luna |
    | Mechanical code edits with explicit checks | self-hosted GLM | GPT-6 Sol / Sonnet 5.5 |
    | Focused low-risk implementation | GPT-6 Luna with clear acceptance checks | GPT-6 Sol / Sonnet 5.5 |
    | General coding, refactoring, substantive review | GPT-6 Sol / Sonnet 5.5 | GPT-6 Astra / Opus 5.5 |
    | Ambiguous debugging, architecture, security, contested findings | parent if capable; otherwise Astra / Opus | Fable for unresolved long-horizon work |
    | Independent-family review | Sonnet/Opus after OpenAI; Sol/Astra after Anthropic | Grok for ordinary, well-bounded changes |
    | Large input | retrieve relevant files first; partition by subsystem | supported large-context lane, including Gemini |

    OpenCode IDs (check `opencode models <provider>` before first use):
    - Personal OpenAI: `openai/gpt-6-luna`, `openai/gpt-6-sol`, `openai/gpt-6-astra`.
    - Work gateway: `hhdev-anthropic/claude-sonnet-5-5`,
      `hhdev-anthropic/claude-opus-5-5`, `hhdev-anthropic/claude-fable-5-1`.
      On hosts with direct Anthropic configured, the same IDs use `anthropic/`.
    - Self-hosted: `hhdev-gemma4-26b/google/gemma-4-26B-A4B-it`,
      `hhdev-glm5-fp8/zai-org/GLM-5.3-Flash`; backup
      `hhdev-deepseek-v4-flash/deepseek-ai/DeepSeek-V4-Flash-0731`.
    - Existing alternatives: `hhdev-grok/grok-4.6`,
      `hhdev-google/gemini-3.1-pro-preview`, `hhdev-google/gemini-3.8-flash`.
    - Gateway OpenAI fallback: `hhdev-openai/gpt-6-sol` or
      `hhdev-openai/gpt-6-astra`, only with Responses tool support confirmed.
      Existing `openai/gpt-5.6-sol`, `openai/gpt-5.6-terra`, and
      `hhdev-openai/gpt-5.5` remain compatibility fallbacks when available.

    Catalog presence proves configuration, not access or working tool calls.
    Use the first scoped task to check tool execution and a usable final result.
    A native runtime's advertised model IDs and tool schema take precedence
    over these OpenCode spellings. Never send `provider/model` to a native
    model selector that expects a bare ID.

    Effort is per model and adapter: inspect supported variants; omit
    `--variant` when unknown. For GPT-6 start low for extraction, medium for
    coding, high for difficult reasoning; raise further only for a specific
    unresolved problem. Astra cannot use `none`; use Responses for reasoning
    with tools across GPT-6. Claude: start with the harness default (Sonnet
    5.5 high, Opus 5.5 medium); increase only after checking missing context.
    Do not apply fixed thinking budgets or sampling knobs blindly to new
    adaptive models. Gemma/GLM/DeepSeek thinking follows provider config,
    not OpenCode effort names. Gemma currently has thinking enabled.

    Self-hosted models and Luna may gather review evidence; substantive
    correctness/security verdicts use Sol/Sonnet or stronger. Two GPT tiers
    are still the same family. Ask reviewers different questions before
    spending on more reviewers. A giant window alone does not justify
    sending a whole repo or adding a mandatory Gemini reviewer.

    ## Harness selection

    - Claude Code: use a native subagent for a bounded same-provider task;
      use supported `sonnet`/`opus`/`haiku` selectors, checking resolved versions.
      Sonnet 5.5 needs Claude Code >= 2.1.284; Opus 5.5 >= 2.1.280.
      Use OpenCode for another provider or the self-hosted lane.
    - OpenCode: use its task tool for an appropriate existing subagent, or
      `opencode run` for explicit model selection and isolated sessions.
    - ChatGPT Work / Codex app: use exposed native collaboration tools when
      available, and their advertised model/effort options. When selecting
      a model requires a fresh context, send a compact brief instead of a
      full history fork. Use local OpenCode only when shell access exists.
      The app's model picker is account-managed, not this Nix catalog.
      Translate skill references to the available skill loader or file reader;
      Claude names such as Task/Skill are not required native tool names.
    - Respect the active runtime's delegation limits. Workers return to the
      parent; they do not recursively fan out unless assigned that role.

    ## Worker contract

    Supply the goal and acceptance checks, absolute working directory,
    repository identity/remote, relevant paths and base/head revisions,
    owned files, read-only or edit authority, and expected output. Include
    only relevant context plus pointers to source files. Debugging workers
    load `diagnosing-bugs`; testable implementation uses `tdd`.

    Each worker returns changed files or findings, supporting path/line or
    command evidence, checks actually run and their outcomes, uncertainties,
    and session ID. Keep reports concise; preserve full logs as artifacts.
    The parent checks claims against the actual target and verifies results.
    Worker confidence and reviewer agreement are not evidence.

    Pin external targets: derive owner/repo from `git remote -v` and the
    task, pass `gh --repo` or tea's `-R <remote>` explicitly, and specify
    cluster/context on every Kubernetes/Helm command. Read-only tasks stay
    read-only. Match exact identifiers and tracked paths before reporting
    findings (`git ls-files` distinguishes repo code from local leftovers).

    Editing workers get separate worktrees or disjoint owned paths; shared
    indexes and overlapping edits require serialization. Before committing,
    inspect `git status` and `git diff --cached`; stage only task paths.
    Preserve others' staged work rather than unstaging it. Stop before a
    commit that would include unrelated staged changes. Workers never
    commit, push, post messages, deploy, or invoke `/ship` unless that exact
    action is assigned and authorized. Parent authorization and repo policy
    travel with the brief; delegation creates no new authority.

    ## Dispatch and recovery

    For OpenCode, save the brief inside the worker's repo in a unique scratch
    directory, kept out of commits. Attach it with `--file`; do not interpolate
    multiline prompts through shell quoting. Example (replace paths/ID):

    ```bash
    opencode run --dir /absolute/worktree -m openai/gpt-6-sol --variant medium \
      --title "bounded task" --format json \
      --file /absolute/worktree/.scratch/task-unique/brief.md \
      -- "Read the attached brief and complete only the assigned task."
    ```

    Capture exit status, event log, and session ID. Reuse that session with
    `--session <id> --dir <same-worktree>` for one concrete correction. Keep
    scratch files in scope for the worker's file permissions. Use existing
    wrapper networking; changing global proxy settings is not a retry step.
    Start with at most two workers; increase only for disjoint work and
    available quota, never beyond runtime limits. Parent continues useful
    work while they run, then joins and verifies before integration.

    On bad ID or unsupported parameters, check the catalog/adapter once and
    correct the request. On 429 honor Retry-After or switch lanes; mark the
    affected model unavailable for the run, not every provider without
    evidence. A pyn.ru outage excludes its self-hosted lanes; an hhdev.ru
    outage excludes its work gateway lanes; a fwdproxy failure excludes
    personal OpenAI routing. Choose a capable remaining lane or self-cover
    and disclose reduced independence. Never lower a security review's bar.
    After one failed correction, escalate once with the evidence or take
    over. Set a task-appropriate deadline; cancel only workers/processes
    started for this task, never kill an ambient server or a port owner.

    Run required repo checks and tests that cover changed behavior. Once
    they pass, repeat only after relevant edits or new evidence of risk.
    Report `task → model/effort → result → verification`, including blocked
    checks and fallbacks. Continue authorized work without new approval
    pauses; explain the exact repo/runtime rule if approval is required.
  '';
}
