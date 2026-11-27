let
  issueBodyTemplate = ''
    ## Цель
    ${"<goal>"}

    ## Почему
    ${"<why>"}

    ## Входит в scope
    ${"<in_scope>"}

    ## Вне scope
    ${"<out_scope>"}

    ## Критерии готовности
    ${"<acceptance_criteria>"}

    ## Заметки по реализации
    ${"<implementation_notes>"}

    ## Milestone / связанный контекст
    ${"<milestone_context>"}
  '';

  handoffTemplate = ''
    <!-- AI-HANDOFF -->
    **AI-HANDOFF**

    **Status:** ${"<status>"}
    **Issue:** #${"<issue_number>"}
    **Branch:** ${"<branch>"}
    **PR:** ${"<pr>"}
    **Jira:** ${"<jira>"}

    **Next step:** ${"<next_step>"}

    **Blockers:** ${"<blockers>"}

    **Decision log:** ${"<decision_log>"}

    **Files/areas:** ${"<files_areas>"}

    **Verification left:** ${"<verification_left>"}

    **Commit status:** ${"<commit_status>"}
  '';

  statusValues = [
    "brainstorming"
    "planned"
    "in-progress"
    "blocked"
    "ready-for-commit"
    "ready-for-pr"
    "pr-open"
    "merged"
  ];

  commitStatusValues = [
    "not-committed"
    "ready"
    "committed"
  ];

  # Single source of truth for Forgejo CLI access rules, interpolated into
  # every workflow skill. Edit here, not in the individual skills.
  forgejoConventions = ''
    Forgejo conventions (shared across workflow skills):
    - Issues, pull requests, comments, labels and milestones go through `fj`. Actions runs and logs go through `fj-ex` (skill `forgejo-ci`). GitHub repos go through `gh --repo <owner/repo>`.
    - Resolve the target from `git remote -v` and the task, and put `-R <forgejo-remote>` directly after the command group on every call: `fj issue -R <forgejo-remote> ...`, `fj pr -R <forgejo-remote> ...`, `fj milestone -R <forgejo-remote> ...`. That position works for all three groups.
    - Read an issue with `fj issue -R <forgejo-remote> view <issue-number>` and its thread with `fj issue -R <forgejo-remote> view <issue-number> comments`. Bodies print as raw markdown, so a handoff is the comment carrying the `<!-- AI-HANDOFF -->` marker; older handoffs carry only the `**AI-HANDOFF**` heading and count too.
    - Post handoffs and comments with `fj issue -R <forgejo-remote> comment <issue-number> $'...'` — the body always given, as one safely quoted argument; a call without a body opens an editor and hangs. Heredocs, command substitution, and backgrounded comment commands break under this shell.
    - Every AI-HANDOFF carries both the hidden `<!-- AI-HANDOFF -->` marker and a visible `**AI-HANDOFF**` heading, and contains workflow content only (status, decisions, next steps). System reminders, tool diagnostics, and internal policy text stay out.
    - When runtime mode or permissions block posting: say so plainly and return the exact body for the user to post manually. Tokens, `curl`, config files, and API auth are not fallbacks to probe.
    - Other subcommands and flags: `fj <group> <command> --help`.
  '';
in
{
  inherit
    issueBodyTemplate
    handoffTemplate
    statusValues
    commitStatusValues
    forgejoConventions
    ;

  formatIssueBody =
    args:
    builtins.foldl' (
      str: name: builtins.replaceStrings [ "<${name}>" ] [ (args.${name} or "") ] str
    ) issueBodyTemplate (builtins.attrNames args);

  formatHandoff =
    args:
    let
      defaults = {
        status = "in-progress";
        issue_number = "";
        branch = "";
        pr = "none";
        jira = "none";
        next_step = "";
        blockers = "none";
        decision_log = "";
        files_areas = "";
        verification_left = "";
        commit_status = "not-committed";
      };
      final = defaults // args;
    in
    builtins.foldl' (
      str: name: builtins.replaceStrings [ "<${name}>" ] [ (final.${name} or "") ] str
    ) handoffTemplate (builtins.attrNames final);

  formatPrTitle =
    args:
    let
      jiraRef = args.jira_ref or "";
      jiraPart = if jiraRef != "" then "${jiraRef} " else "";
    in
    "#${builtins.toString (args.issue_number or "")} ${jiraPart}${args.human_title or ""}";

  formatBranch =
    args:
    let
      parts = builtins.filter (part: part != "") [
        "issue"
        (builtins.toString (args.issue_number or ""))
        (args.jira_ref or "")
        (args.slug or "")
      ];
    in
    builtins.concatStringsSep "-" parts;
}
