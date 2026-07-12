#!/usr/bin/env python3
"""Standalone unit tests for the structured-output-from-transcript patch.

Runs with no third-party deps, no nix build, and no network:

    python3 test_structured_output.py

It extracts the pure functions added by structured-output-from-transcript.patch
straight from the patch file and exercises them, so the tests track exactly what
ships rather than a hand-copied duplicate.
"""
import json
import os
import re
import glob
import shlex
import sqlite3
import subprocess
import sys

PATCH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "structured-output-from-transcript.patch")


def load_functions():
    """Exec the function block the patch inserts after detect_options()."""
    src_lines = []
    collecting = False
    for ln in open(PATCH, encoding="utf-8").read().splitlines():
        if ln.startswith("@@"):
            if collecting:
                break
            continue
        if not collecting and ln.startswith("+") and "def claude_project_dir" in ln:
            collecting = True
        if collecting:
            if ln.startswith("+"):
                src_lines.append(ln[1:])
            elif ln.startswith("-"):
                continue
            else:
                break
    if not any("def transcript_to_blocks" in l for l in src_lines):
        raise SystemExit("could not extract function block from patch")
    ns = {
        "re": re, "json": json, "os": os, "glob": glob, "shlex": shlex,
        "subprocess": subprocess, "sqlite3": sqlite3,
        "CLAUDE_PROJECTS": "~/.claude/projects",
        "OPENCODE_DB": "~/.local/share/opencode/opencode-stable.db",
        "TRANSCRIPT_MAX_BYTES": 262144,
        "TRANSCRIPT_BLOCK_LIMIT": 200,
        "pane_cwd_map": {},
    }
    exec("\n".join(src_lines), ns)
    return ns


FN = load_functions()
claude_project_dir = FN["claude_project_dir"]
summarize_tool = FN["summarize_tool"]
transcript_to_blocks = FN["transcript_to_blocks"]
pane_blocks = FN["pane_blocks"]
opencode_to_blocks = FN["opencode_to_blocks"]

failures = []


def check(name, got, want):
    if got != want:
        failures.append(f"{name}\n  got:  {got!r}\n  want: {want!r}")


# --- claude_project_dir: '/', '.', '_' all collapse to '-' -------------------
check("project_dir_basic",
      claude_project_dir("/Users/sab/git_priv/herdr-mobile"),
      "-Users-sab-git-priv-herdr-mobile")
check("project_dir_dots_underscores",
      claude_project_dir("/home/me/my_app.v2"),
      "-home-me-my-app-v2")

# --- summarize_tool: first descriptive field, first line, capped -------------
check("summarize_file_path",
      summarize_tool({"file_path": "/etc/hosts", "content": "x"}),
      "/etc/hosts")
check("summarize_command_first_line",
      summarize_tool({"command": "make build\n&& make test"}),
      "make build")
check("summarize_prefers_earlier_key",
      summarize_tool({"pattern": "TODO", "command": "grep TODO"}),
      "grep TODO")  # 'command' precedes 'pattern' in the priority list
check("summarize_empty", summarize_tool({}), "")
check("summarize_non_dict", summarize_tool(None), "")

# --- transcript_to_blocks: full mapping over a mixed fixture -----------------
FIXTURE = "\n".join(json.dumps(r) for r in [
    {"type": "mode", "mode": "default"},                       # meta -> skipped
    {"type": "user", "isMeta": True,
     "message": {"role": "user", "content": "boot"}},          # isMeta -> skipped
    {"type": "user",
     "message": {"role": "user", "content": "Fix the login bug"}},
    {"type": "user",
     "message": {"role": "user",
                 "content": "<command-name>/clear</command-name>"}},  # command wrapper -> skipped
    {"type": "assistant",
     "message": {"role": "assistant", "content": [
         {"type": "thinking", "thinking": "Let me look\nat the code"},
         {"type": "text", "text": "I'll check `auth.py`."},
         {"type": "tool_use", "name": "Read", "input": {"file_path": "auth.py"}},
     ]}},
    {"type": "user",
     "message": {"role": "user", "content": [
         {"type": "tool_result", "content": "def login(): ..."}]}},  # list content -> skipped
    {"type": "assistant",
     "message": {"role": "assistant", "content": [
         {"type": "text", "text": "Found it."}]}},
])

blocks = transcript_to_blocks(FIXTURE)
kinds = [(b["kind"], b.get("label")) for b in blocks]
check("blocks_sequence", kinds, [
    ("status", "You"),
    ("status", "Thought"),
    ("assistant_text", None),
    ("tool", "Read"),
    ("assistant_text", None),
])
check("blocks_thought_first_line", blocks[1]["text"], "Let me look")
check("blocks_you_text", blocks[0]["text"], "Fix the login bug")
check("blocks_assistant_markdown", blocks[2]["markdown"], "I'll check `auth.py`.")
check("blocks_tool_summary", blocks[3]["text"], "auth.py")
check("blocks_ids_present", [b["id"] for b in blocks], ["b0", "b1", "b2", "b3", "b4"])

# --- transcript_to_blocks: robustness ---------------------------------------
check("blocks_empty", transcript_to_blocks(""), [])
check("blocks_partial_first_line",
      [b["kind"] for b in transcript_to_blocks(
          'partial-json-cut-off\n' + json.dumps(
              {"type": "assistant", "message": {"role": "assistant",
               "content": [{"type": "text", "text": "ok"}]}}))],
      ["assistant_text"])

limited = transcript_to_blocks(
    "\n".join(json.dumps(
        {"type": "assistant", "message": {"role": "assistant",
         "content": [{"type": "text", "text": str(i)}]}}) for i in range(250)),
    limit=10)
check("blocks_limit_tail", [b["markdown"] for b in limited],
      [str(i) for i in range(240, 250)])

# --- pane_blocks: never guess between concurrent sessions in one cwd --------
FN["pane_cwd_map"]["ambiguous"] = ("/work/repo", "claude", None, True)
check("ambiguous_cwd_skipped", pane_blocks("ambiguous"), (None, None))

# --- opencode_to_blocks: SQLite message/part mapping -------------------------
OPENCODE_FIXTURE = {
    "session_id": "ses_test",
    "updated": 1,
    "rows": [
        ["user", json.dumps({"type": "text", "text": "Fix the login bug"})],
        ["assistant", json.dumps({"type": "step-start"})],
        ["assistant", json.dumps({"type": "reasoning", "text": "Inspect auth\nthen patch"})],
        ["assistant", json.dumps({"type": "text", "text": "I'll inspect it."})],
        ["assistant", json.dumps({"type": "tool", "tool": "read", "state": {
            "status": "completed", "input": {"filePath": "auth.py"}}})],
        ["assistant", "not-json"],
    ],
}
opencode_blocks = opencode_to_blocks(OPENCODE_FIXTURE)
check("opencode_sequence",
      [(b["kind"], b.get("label")) for b in opencode_blocks],
      [("status", "You"), ("status", "Thought"),
       ("assistant_text", None), ("tool", "read")])
check("opencode_reasoning_first_line", opencode_blocks[1]["text"], "Inspect auth")
check("opencode_markdown", opencode_blocks[2]["markdown"], "I'll inspect it.")
check("opencode_tool_summary", opencode_blocks[3]["text"], "auth.py")


if failures:
    print(f"FAILED ({len(failures)}):\n" + "\n\n".join(failures))
    sys.exit(1)
print("all structured-output relay tests passed")
