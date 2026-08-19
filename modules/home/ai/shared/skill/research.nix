# Adapted from mattpocock/skills `research` (plugin v1.2.3) — background-agent
# dispatch and the primary-source rule, extended with the MCP indexes available
# here and with the investigation-issue flow `brainstorm` creates on a fog check.
{
  name = "research";
  version = "1.0.0";
  description = "Investigate a question against primary sources and capture the findings as a cited Markdown file. Use when the user wants a topic researched, docs or API facts gathered, an investigation issue resolved, or reading legwork delegated to a background agent.";
  allowed-tools = [
    "Read"
    "Grep"
    "Glob"
    "Bash"
    "Task"
    "Write"
    "WebFetch"
    "WebSearch"
  ];
  content = ''
    Investigate a question against primary sources and leave the findings behind as a cited Markdown file. The reading is delegable; the conclusions are yours.

    ## Dispatch

    Run the reading in a **background agent** so the main session keeps working. When the volume is large and the question is already sharp, route it through `delegate` to a cheap model instead — bulk reading is grunt work.

    Verify what comes back. An unsourced claim is a failed research task, whoever produced it.

    ## Sources

    Go to the source that **owns** the fact: official docs and specs, upstream source code, first-party API references, RFCs, release notes and changelogs.

    Reach for the indexes that answer authoritatively before searching the open web:
    - `nixos` MCP for nixpkgs packages, NixOS / home-manager / darwin options, channels, flakes, and store paths — it queries the live indexes, so it beats both web search and parametric memory.
    - `context7` MCP for library, framework, and SDK documentation.
    - The repo, the cluster, or the running config when the question is *what is actually configured here* — the environment is the source of truth for its own state, and no doc outranks it.

    Follow every claim back to its owning source. Blog posts, forum answers, and model memory are leads to check, never citations. Where authoritative sources disagree, say so and name which one governs.

    ## Output

    One Markdown file:
    - Every claim carries its source — a link, a file path, or the command that produced it.
    - Anything that rots is stamped with its version or date: package versions, API shapes, channel state, cluster config.
    - A claim you could not source is written down as unverified. Do not drop it, and do not smooth it over.
    - Answer the question that was asked first; supporting detail after.

    Save it where the repo already keeps notes — match the existing convention. If there is none, pick a sensible path and say where you put it.

    ## Closing an investigation issue

    When the research resolves an investigation issue (the kind `brainstorm` files on a fog check), the file is the artifact: link it from the issue, and put the answer itself in the AI-HANDOFF decision log. The next session should inherit the finding, not the reading list.
  '';
}
