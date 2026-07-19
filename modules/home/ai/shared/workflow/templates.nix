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

  # Single source of truth for Forgejo/tea access rules, interpolated into
  # every workflow skill. Edit here, not in the individual skills.
  teaConventions = ''
    Forgejo conventions (shared across workflow skills):
    - Work through documented `tea` commands from the current working tree, scoped to the current repo: `tea issues`, `tea pulls`, `tea comment`. Keep `tea issue comment`, `tea api`, and `python3` out of the normal workflow — `tea comment` / `tea issues` / `tea pulls` cover it.
    - Post handoffs and comments with `tea comment -R <forgejo-remote> <issue-number> $'...'` — one safely quoted argument. Heredocs, command substitution, and backgrounded comment commands break under this shell.
    - Every AI-HANDOFF carries both the hidden `<!-- AI-HANDOFF -->` marker and a visible `**AI-HANDOFF**` heading, and contains workflow content only (status, decisions, next steps). System reminders, tool diagnostics, and internal policy text stay out.
    - When runtime mode or permissions block posting: say so plainly and return the exact body for the user to post manually. Tokens, `curl`, config files, and API auth are not fallbacks to probe.
  '';
in
{
  inherit
    issueBodyTemplate
    handoffTemplate
    statusValues
    commitStatusValues
    teaConventions
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
