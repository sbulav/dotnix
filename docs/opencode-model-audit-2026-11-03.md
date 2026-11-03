# OpenCode model audit — 2026-11-03

## Recommendation

Add GPT-6.1 Sol, GPT-6.1 Terra, and Claude Haiku 5.5. Trial Gemini 4 Argon.
Fix custom-provider metadata before relying on larger contexts or cost-based routing.
Keep the free GLM default until comparative task checks justify changing it.
These recommendations compare repository configuration, live gateway inventories, and official model documentation. [R1], [R2], [O1], [A1], [G1].

The initial audit used model-list GET requests and the local OpenCode catalog, not inference.
The implementation and inference checks below followed user approval. Inventory presence alone
does not establish successful generation, streaming, tool calls, quotas, or billing.
The installed CLI reports `opencode v2.2.1`; its built-in OpenAI catalog already includes both GPT-6.1 additions.
Sources: `opencode --version`, `opencode api get /api/model`, and the gateway endpoints below, queried on 2026-11-03.

## Initial inventory and model decisions

| Provider | Current configuration | Recommendation and evidence |
|---|---|---|
| `openai`, `hhdev-openai` | Shared GPT-6 Sol, Astra, Luna; gateway also has GPT-5.5 and GPT-5.6 fallbacks | Add `gpt-6.1-sol` and `gpt-6.1-terra` to the shared catalog. Prefer 6.1 Sol for the existing general-coding role. Terra is an optional visual/computer-use/writing lane, not a replacement for Astra. Both IDs appear in hhdev's live inventory and official docs. Keep Astra and Luna. [R1], [R2], [H1], [O1], [O2], [O3]. |
| `hhdev-anthropic` | Sonnet 5.5, Opus 5.5, Fable 5.1; older Opus fallbacks | Add `claude-haiku-5-5`; keep the other current models. Haiku 5.5 appears in the gateway inventory and official current lineup. [R1], [R2], [H2], [A1], [A2]. |
| Direct Anthropic on `mba13` | Shared models plus Haiku 4.5; `small_model` explicitly uses Haiku 4.5 | Consider switching this host's small model to Haiku 5.5 after an account-level check. The shared addition makes the new ID explicit on this host too. Direct account access was not tested. [R4], [A2]. |
| `hhdev-google` | Gemini 3.1 Pro Preview and 3.8 Flash | Add `gemini-4-argon` as a trial reasoning/coding lane. Keep 3.8 Flash for speed and retain 3.1 Pro as a fallback until task checks establish a replacement. Argon is stable in Google's October 2026 documentation and appears in hhdev's inventory. [R2], [H3], [G1], [G2]. |
| `hhdev-grok` | Grok 4.7 | No version bump: xAI still recommends 4.7 for coding and chat, and hhdev lists it. Correct or document the pricing discrepancy below. [R2], [H4], [X1]. |
| `hhdev-glm5-fp8` | GLM-5.3 Flash, default model | No model-ID bump: this endpoint still serves `zai-org/GLM-5.3-Flash`. Its reported deployment context is now 262,144, versus 131,072 configured locally. [R2], [R3], [H6]. |
| `hhdev-gemma4-26b` | Gemma 4 26B A4B, default small model | Do not rename or bump blindly: `/models` returns only `id: "unknown"`. Validate the configured ID with generation before changing it. This response alone does not prove the configured model is broken. [R2], [R3], [H7]. |
| `hhdev-deepseek-v4-flash` | Self-hosted DeepSeek V4 Flash 0731 | No model-ID bump available on this endpoint. Set an explicit context limit of 131,072, matching the deployed inventory. Do not apply public V4.1 limits to this older deployment. [R2], [H8]. |
| `hhdev-deepseek` | `deepseek-flash`, `deepseek-v4-pro`, with 2,048/4,096-token settings | Re-evaluate rather than rename: the gateway now labels `deepseek-flash` as V4.1 Flash. DeepSeek's official alias currently serves V4.1-Flash-1017. Check the old output-budget restrictions before restoring this route. Neither actual gateway output capacity nor tool behavior was tested. [R2], [H5], [D1]. |

## Metadata fixes are as important as model bumps

### Custom hhdev entries lose built-in catalog details

Before the update, the resolved catalog reported these values rather than the upstream specifications:

| Resolved model | Runtime context | Runtime output | Evidence |
|---|---:|---:|---|
| `hhdev-openai/gpt-6-sol` | 200,000 | 32,000 | `opencode api get /api/model` |
| `hhdev-anthropic/claude-sonnet-5-5` | 200,000 | 32,000 | Same command |
| `hhdev-google/gemini-3.8-flash` | 200,000 | 32,000 | Same command |
| Self-hosted DeepSeek V4 Flash 0731 | 200,000 | 32,000 | Same command; backend reports only 131,072 context [H8] |
| Self-hosted GLM-5.3 Flash | 131,072 | 32,768 | Same command; backend reports 262,144 context [H6] |

OpenCode documents 200,000/32,000 as fallback values for unknown custom models.
Its V2 provider configuration supports `canonical` to inherit a built-in provider's catalog defaults.
Use canonical inheritance for matching upstream models, or explicit verified capabilities and limits.
Keep deployment-specific limits for self-hosted models. Do not infer their capabilities from public model-family specs. [OC1], [OC2].

The DeepSeek mismatch risks sending oversized requests. The GLM mismatch unnecessarily reduces usable context.
The Claude/Gemini/GPT values are fallback metadata, not evidence that hhdev enforces those limits.
For example, hhdev's Gemini 3.8 inventory reports 1,048,576 input and 65,536 output tokens. [H3], [H6], [H8], [OC1].

Argon needs particular care: hhdev's model inventory reports 32,768 output tokens,
while Google's documentation specifies 65,536 synchronous output and a shared 1,048,576-token context.
Use conservative gateway limits until an actual request establishes supported behavior. [H3], [G2].

### Grok pricing is understated by 10× versus public prices

Before the update, the repository configured Grok 4.7 input/output at **$0.20/$0.60** per million tokens,
with cached input at **$0.05**. xAI publishes **$2/$6**, with cached input at **$0.50**.
The repository's long-context rates are also 10× below xAI's published rates. [R2], [X1].

The review policy repeats the lower prices and calls Grok a cheap metered lane.
Verify whether hhdev has a documented discount; otherwise correct both the catalog and review policy.
Gateway billing was not available in these checks. [R6], [X1].

### Preserve the right request protocol

GPT-6.1 Sol and Terra require the Responses API for tool calling.
The direct OpenAI entries resolve to `@opencode/ai/providers/openai/responses`.
The existing hhdev GPT entries resolve to `@opencode/ai/providers/openai`, with fallback metadata.
Verify the gateway route uses Responses and completes a tool round trip before promoting the new models. [O2], [O3], [OC2].
Runtime evidence: `opencode api get /api/model` on 2026-11-03.

Haiku 5.5 uses adaptive thinking. Its official guide says to omit `temperature`, `top_p`, and `top_k`.
Do not transfer old fixed thinking-budget or sampling settings indiscriminately. [A2]

## Suggested implementation order

1. Correct self-hosted DeepSeek context metadata; verify Grok billing and correct prices if no discount exists.
2. Add GPT-6.1 Sol/Terra and Haiku 5.5 to the shared catalog; add Argon to the Google provider.
3. Restore accurate upstream metadata inheritance, preserving deployment-specific overrides and existing credentials.
4. Run small streaming and tool-round-trip checks through OpenCode, including gateway Responses requests.
5. Update routing references from GPT-6 Sol to 6.1 Sol, GLM context descriptions, and the Grok cost ordering.
6. Change the Mac's Haiku selection only after its direct Anthropic account passes a check.

The checklist above records the proposed scope. Implementation results follow. Relevant files: [R1]–[R6].
No reason was established here to bump the OpenCode binary merely to expose GPT-6.1:
the installed catalog already includes it. This was not a broader OpenCode release audit.

## Implementation and validation

Implemented on 2026-11-03, without activation or a flake-input update:

- Added GPT-6.1 Sol/Terra and Haiku 5.5 to the shared catalog, and Argon to hhdev Google.
- Converted provider entries to native V2 syntax. Canonical inheritance now supplies upstream
  capabilities, reasoning variants, prices, and limits. Gateway GPT explicitly uses Responses over HTTP.
- Corrected GLM context to 262,144, self-hosted DeepSeek context to 131,072,
  and Grok public pricing. Self-hosted reasoning template controls remain in request bodies.
- Updated shared routing and review lanes; Grok is no longer described as a $0.20/$0.60 cheap reviewer.
- Kept GLM as default, Gemma as the Linux small model, and the Mac's direct Haiku 4.5 small model.
  Haiku 5.5 is available in the Mac's direct catalog, but that account could not be tested here.

Sources: [R1], [R2], [R3], [R4], [R5], [R6]. The generated `opencode.json` was evaluated
for `mz`, `nz`, and `mba13`; assertions covered model availability, transports, limits,
the Claude compatibility override, and unchanged defaults. All passed.

### Gateway compatibility found by inference checks

The first native Claude requests failed with HTTP 400:
`thinking.adaptive.block_binding: Extra inputs are not permitted`.
Setting model-level `compatibility.supportsThinkingBlockBinding = false` on hhdev Claude
models fixed Haiku and Sonnet. Direct Anthropic is unaffected. [R2], [OC1].

The probe used an isolated project under `/tmp/opencode/model-bump`, a synthetic text fixture,
and an agent allowed only to read that fixture. Each passing run executed a read tool and
returned the fixture's exact contents. The initial Sol attempt exposed a probe permission-pattern
mismatch; allowing `*fixture.txt` fixed the harness before the model checks continued.

Command shape, run from that isolated project:

```sh
opencode --standalone run --agent model-probe --model 'PROVIDER/MODEL#low' \
  --title 'Model smoke' --format json \
  'Read fixture.txt with the read tool and reply with exactly its contents. Do not edit files or run commands.'
```

Self-hosted models omitted `#low`, retaining their configured template controls.

| Gateway model | Result | Passing session |
|---|---|---|
| GPT-6.1 Sol | PASS, Responses tool round trip | `ses_e5f43c4a5ffewaZfoqyc2TXOLs` |
| GPT-6.1 Terra | PASS, Responses tool round trip | `ses_e5f436721ffe5HCR792HUL71A3` |
| Haiku 5.5 | PASS after compatibility override | `ses_e5f429146ffeBmCYGyF6t6fITE` |
| Sonnet 5.5 | PASS after compatibility override | `ses_e5f42912bffeWM8gFIekeZ3k2U` |
| Gemini 4 Argon | PASS | `ses_e5f436093ffegDpvkbf0696mHA` |
| Gemini 3.8 Flash | PASS | `ses_e5f4352e1ffe8CJvEConxGj4Ga` |
| Grok 4.7 | PASS | `ses_e5f43356dffeIYgF1vtIm17gTL` |
| Self-hosted GLM-5.3 Flash | PASS | `ses_e5f432389ffeWc63nsWKJfGv6g` |
| Self-hosted Gemma 4 | PASS despite `unknown` inventory ID | `ses_e5f431664ffeeya9VRE6vmEhmH` |
| Self-hosted DeepSeek V4 Flash 0731 | PASS | `ses_e5f430efeffeFNRYcoBdUuI4dC` |
| Gateway DeepSeek Flash | PASS with existing output budget | `ses_e5f430d42ffeilAztanGUMBWoA` |

These checks establish small streaming/tool requests, not full-context capacity,
long-output behavior, comparative coding quality, or gateway billing discounts.
DeepSeek's existing 2,048/4,096 output budgets remain pending larger-output validation.

### Repository checks

- `nix fmt -- <changed Nix paths>` — PASS.
- `nix run --inputs-from . nixpkgs#statix -- check .` — PASS.
- `nix run --inputs-from . nixpkgs#deadnix -- --fail --no-lambda-pattern-names -- .` — PASS.
- `nix flake check --no-update-lock-file` — PASS for the native x86_64-linux checks;
  incompatible-system checks were skipped by Nix.
- `nix build --no-link` for `mz`, `nz`, and `zanoza` system toplevels — PASS.
- `nix eval --raw .#darwinConfigurations.mba13.system.drvPath` — PASS.
- `nix build --no-link .#darwinConfigurations.mba13.system` — BLOCKED by
  `aarch64-darwin`/`x86_64-linux` platform mismatches. No Darwin builder is configured;
  the task's build process was interrupted to stop further dependency downloads.
  Complete this build on the Mac or a configured Darwin builder.

Nix reported binary-cache timeouts and existing derivation-context warnings, but the
Linux builds and checks completed. No switch, test activation, deployment, or commit was run.

### Credential handling incident

A config-API diagnostic unexpectedly printed expanded gateway credentials into tool output.
No credential values were added to repository files. The user was informed that both gateway
keys should be rotated. Subsequent diagnostics use field-filtered output; do not share raw
`/api/config` responses, which contain resolved credentials.

## Evidence sources

All runtime and gateway observations are dated **2026-11-03**.
Inventory and inference requests used existing environment credentials. See the diagnostic
credential-handling incident above; no secret values are included in this document.
Google's inventory was read through both pages: 60 total entries, no remaining page token.
No repository content was sent for inference.

[R1]: ../modules/home/ai/shared/models.nix
[R2]: ../modules/home/ai/opencode/providers.nix
[R3]: ../modules/home/ai/opencode/default.nix
[R4]: ../homes/aarch64-darwin/sab@mba13/default.nix
[R5]: ../modules/home/ai/shared/routing.nix
[R6]: ../modules/home/ai/shared/skill/delegate-review.nix
[H1]: https://llmgtw.hhdev.ru/proxy/openai/models
[H2]: https://llmgtw.hhdev.ru/proxy/anthropic/v1/models
[H3]: https://llmgtw.hhdev.ru/proxy/google/v1beta/models
[H4]: https://llmgtw.hhdev.ru/proxy/xai/models
[H5]: https://llmgtw.hhdev.ru/proxy/deepseek/models
[H6]: https://llm-gateway.pyn.ru/proxy/glm5-fp8/v1/models
[H7]: https://llm-gateway.pyn.ru/proxy/gemma-4-26b-a4b-it/v1/models
[H8]: https://llm-gateway.pyn.ru/proxy/deepseek-v4-flash-0731/v1/models
[O1]: https://developers.openai.com/api/docs/models
[O2]: https://developers.openai.com/api/docs/models/gpt-6.1-sol
[O3]: https://developers.openai.com/api/docs/models/gpt-6.1-terra
[A1]: https://platform.claude.com/docs/en/about-claude/models/overview
[A2]: https://platform.claude.com/docs/en/models/haiku-5-5/overview
[G1]: https://ai.google.dev/gemini-api/docs/models
[G2]: https://aistudio.google.com/docs/models/gemini-4-argon
[X1]: https://docs.x.ai/developers/models
[D1]: https://api-docs.deepseek.com/quick_start/pricing
[OC1]: https://opencode.ai/v2/docs/models
[OC2]: https://opencode.ai/v2/docs/providers
