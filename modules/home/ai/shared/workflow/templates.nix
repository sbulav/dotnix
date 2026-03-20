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
in
{
  inherit
    issueBodyTemplate
    handoffTemplate
    statusValues
    commitStatusValues
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
