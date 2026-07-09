# Adapted from mattpocock/skills `diagnosing-bugs`. Model-invoked on purpose:
# debugging sessions rarely announce themselves upfront, so the agent must be
# able to reach for this discipline mid-flight.
{
  name = "diagnosing-bugs";
  version = "1.0.0";
  description = "Diagnosis loop for hard bugs, flaky failures, and performance regressions. Use when the user says diagnose/debug/root-cause, reports something broken, throwing, failing, flaky, or slow, or when a previous fix did not hold.";
  allowed-tools = [
    "Read"
    "Grep"
    "Glob"
    "Bash"
    "Task"
    "Write"
    "Edit"
  ];
  content = ''
    A discipline for hard bugs. Skip phases only when explicitly justified.

    Before diving in, check ADRs and runbooks in the area you're touching, if the repo keeps them.

    ## Phase 1 — Build a feedback loop

    **This is the skill.** Everything else is mechanical. If you have a **tight** pass/fail signal for the bug — one that goes red on *this* bug — you will find the cause; bisection, hypothesis-testing, and instrumentation all just consume it. Without one, no amount of staring at code will save you.

    Spend disproportionate effort here. Be aggressive. Be creative. Refuse to give up.

    Ways to construct one, in rough order:
    1. **Failing test** at whatever seam reaches the bug — unit, integration, e2e.
    2. **Curl / HTTP script** against a running dev server or live endpoint.
    3. **CLI invocation** with a fixture input, diffing output against a known-good snapshot.
    4. **kubectl/journalctl probe loop** — a script that applies the trigger and greps the resulting state or logs for the symptom.
    5. **Replay a captured trace.** Save a real request / payload / event log and replay it through the code path in isolation.
    6. **Throwaway harness.** Spin up a minimal subset of the system (one service, mocked deps) that exercises the bug path with a single call.
    7. **Property / fuzz loop.** If the bug is "sometimes wrong output", run many random inputs and look for the failure mode.
    8. **Bisection harness.** If the bug appeared between two known states (commit, generation, version), automate "boot at state X, check, repeat" so `git bisect run` can consume it.
    9. **Differential loop.** Run the same input through old vs new version (or two configs) and diff outputs.
    10. **HITL script.** Last resort: if a human must click or listen, drive them with a short script that prompts step by step and captures their answers, so the loop stays structured.

    Once you have *a* loop, **tighten** it: faster (cache setup, narrow the scope), sharper (assert the specific symptom, not "didn't crash"), more deterministic (pin time, seed RNG, isolate filesystem, freeze network).

    Non-deterministic bugs: the goal is a **higher reproduction rate**, not a clean repro. Loop the trigger 100×, parallelise, add stress, narrow timing windows. A 50%-flake is debuggable; 1% is not.

    Environment limits: if the loop needs network or cluster access this runtime cannot reach, hand the exact command to the user to run in their shell **once you have written and dry-checked it** — a human-executed loop is still a loop. State clearly which part is blocked.

    **Completion criterion — a tight loop that goes red.** You can name one command that you have already run at least once (paste the invocation and output), and that is:
    - [ ] **Red-capable** — asserts the user's exact symptom; can go red on this bug and green once fixed.
    - [ ] **Deterministic** — same verdict every run (or a pinned, high reproduction rate).
    - [ ] **Fast** — seconds, not minutes.

    If you catch yourself reading code to build a theory before this command exists, stop — jumping straight to a hypothesis is the exact failure this skill prevents.

    ## Phase 2 — Reproduce + minimise

    Run the loop. Watch it go red. Confirm the loop produces the failure mode the **user** described — a nearby different failure means wrong bug, wrong fix. Capture the exact symptom for later verification.

    Then shrink the repro to the smallest scenario that still goes red: cut inputs, callers, config, and steps one at a time, re-running after each cut. Done when every remaining element is load-bearing.

    ## Phase 3 — Hypothesise

    Generate **3–5 ranked hypotheses** before testing any. Single-hypothesis generation anchors on the first plausible idea — and root causes often hide in layers: the obvious cause can sit on top of the real one.

    Each hypothesis must be falsifiable: "If <X> is the cause, then <changing Y> makes the bug disappear / <changing Z> makes it worse." If you cannot state the prediction, it is a vibe — discard or sharpen it.

    Show the ranked list to the user before testing — they often re-rank instantly from domain knowledge. Proceed with your own ranking if they are AFK.

    ## Phase 4 — Instrument

    Each probe maps to a specific prediction from Phase 3. Change one variable at a time.

    Tool preference: debugger/REPL inspection first; targeted logs at the boundaries that distinguish hypotheses second. Tag every debug log with a unique prefix like `[DEBUG-a4f2]` so cleanup is a single grep.

    Performance regressions: logs are usually wrong. Establish a baseline measurement (timing harness, profiler, query plan), then bisect. Measure first, fix second.

    ## Phase 5 — Fix + regression test

    Write the regression test **before the fix** — but only at a **correct seam**, one where the test exercises the real bug pattern as it occurs at the call site. A too-shallow seam gives false confidence; if no correct seam exists, that itself is a finding — document it and flag it.

    With a correct seam: turn the minimised repro into a failing test, watch it fail, apply the fix, watch it pass, then re-run the Phase 1 loop against the original un-minimised scenario.

    ## Phase 6 — Cleanup + post-mortem

    Required before declaring done:
    - [ ] Original repro no longer reproduces — re-run the Phase 1 loop against the user's original scenario. First apparent success is not done.
    - [ ] Regression test passes (or the absence of a seam is documented).
    - [ ] All `[DEBUG-...]` instrumentation removed (grep the prefix).
    - [ ] Throwaway harnesses deleted or moved to a clearly-marked debug location.
    - [ ] The winning hypothesis stated in the commit / handoff — so the next debugger learns.

    If the symptom returns later, treat it as a second cause layered under the first: keep the surviving evidence and return to Phase 3, never re-declare the old fix sufficient.

    Then ask: what would have prevented this bug? If the answer is architectural (no good test seam, tangled callers, hidden coupling), suggest `/brainstorm` to file a follow-up issue — after the fix is in, when you know the most.
  '';
}
