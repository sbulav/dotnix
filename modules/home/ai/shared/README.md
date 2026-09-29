# Model routing maintenance

Reviewed 2026-09-29 for Claude Code, OpenCode, and ChatGPT Work / Codex.

`models.nix` owns the current OpenAI/Anthropic catalog, reused by OpenCode
providers, the direct Anthropic provider on mba13, and the Herdr relay's
Claude choices. Gateway entries declare choices; they do not establish
account access. Legacy entries remain explicit compatibility fallbacks.
Claude CLI uses its provider-aware aliases rather than a forced Nix default.
The app's model picker and subscription access remain account-managed.

`routing.nix` owns workload routing, effort, worker contracts and recovery.
Both delegation skills interpolate it. Roles are starting policies, not
invented benchmark scores. Preserve the self-hosted OpenCode default and
small-model settings unless intentionally changing their cost/latency role.

## Evidence behind the refactor

The local Claude usage report `report-2026-09-29-120836.html` identified
wrong approaches (12) and buggy code (10) as its leading friction categories.
Its examples included wrong repo/cluster targets, an unrelated staged change,
unsupported conclusions, fragile worker prompt quoting and scratch paths,
and cleanup killing another service. The report is qualitative evidence for
workflow changes, not a comparative evaluation of the newly released models.
No private report contents or credentials need to be copied into worker briefs.

The revised skills pin targets and revisions, preserve shared state, pass
file-based briefs, isolate edits, diagnose before changing config, and require
source-backed findings. They avoid mandatory worker counts, repeated review
scorecards, blind high effort, and automatic shipping from an implementation
request. `/ship` remains user-invoked. Existing repo activation rules still apply.

## Local app skills

`custom.ai.codex` installs the shared registry to `~/.agents/skills` using
portable name/description metadata and `agents/openai.yaml`. The latter maps
`disable-model-invocation` to `allow_implicit_invocation: false`, preserving
explicit-only planning/shipping entry points. `custom.ai.codex.skills` can
narrow the set when needed. Claude and OpenCode use the same skill bodies.

At activation, existing hand-installed files owned by this module are moved
to `$XDG_STATE_HOME/dotnix/codex-skills-backup/<timestamp>-<pid>/` before Home
Manager checks link targets. Store symlinks are left for Home Manager to
update. The hook honors dry-run mode; builds do not migrate live files.

The `dev` router selects the smallest workflow. `handoff` transfers sessions,
`triage` prepares incoming reports, `prototype` resolves executable design
questions, and `architecture-review` surveys friction in actively changed code.
These adaptations were reviewed against mattpocock/skills v1.2.3, commit
`c55ee46073ed923f86ce59a5eb3b6d895095d1b7`. They keep this repo's Forgejo and
AGENTS.md conventions; they do not install the upstream plugin or its scripts.

## Release checklist

1. Verify exact IDs and compatibility in official docs. Update `models.nix`
   and the workload policy together, preserving explicit fallback roles.
2. Check installed CLI versions and `opencode models <provider>`. A catalog
   listing alone does not prove authenticated access or successful tool use.
3. Check supported reasoning variants and transport. GPT-6 reasoning with
   tools uses Responses; do not assume a gateway implements it. Avoid copying
   old fixed thinking budgets or sampling settings to new adaptive models.
4. Run one bounded, representative task before trusting a new route. Record
   tool success, acceptance checks, latency, retries and quota usage. Compare
   extraction, a tested code change, a seeded-defect review, and diagnosis;
   do not promote a model based solely on its vendor's description.
5. Format/lint, evaluate generated skills and all affected hosts, build,
   and run flake checks. Activate only with explicit approval.

Known compatibility gate: the pinned Claude Code package is 2.1.283 at this
review. Sonnet 5.5 requires >=2.1.284; Opus 5.5 requires >=2.1.280. The catalog
can expose Sonnet 5.5 for OpenCode and newer remote CLIs, but the pinned local
Claude CLI must be upgraded before using it. No flake input was bumped as
part of this model/prompt change. Gateway inference has not been smoke-tested.

## Primary sources

- [OpenAI GPT-6 model and migration guidance](https://developers.openai.com/api/docs/guides/latest-model)
- [OpenAI model catalog](https://developers.openai.com/api/docs/models)
- [Claude Sonnet 5.5](https://platform.claude.com/docs/en/models/sonnet-5-5/overview)
- [Claude Opus 5.5 migration](https://platform.claude.com/docs/en/models/opus-5-5/migration-guide)
- [Claude Code models and minimum CLI versions](https://code.claude.com/docs/en/model-config)
- [OpenCode model configuration and variants](https://opencode.ai/docs/models/)
- [Local app skill discovery](https://learn.chatgpt.com/docs/build-skills)
