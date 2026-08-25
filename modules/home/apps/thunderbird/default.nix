{
  config,
  lib,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.apps.thunderbird;
in
{
  options.custom.apps.thunderbird = {
    enable = mkEnableOption "Thunderbird with the declarative work Exchange (IMAP) account";

    address = mkOpt types.str "s.bulavintsev@hh.ru" "Work mailbox address.";

    owaStyle = mkBoolOpt true "Whether to use an Office Outlook Web Access-inspired interface.";

    # On-prem Exchange wants the short login without the domain; the IT doc's
    # manual-setup warning about "Re-test" silently switching auth to Kerberos
    # does not apply here because the declarative account pins password auth.
    login = mkOpt types.str "s.bulavintsev" "IMAP/SMTP login (short, no domain).";

    host = mkOpt types.str "email.hh.ru" ''
      Mail server host. On-prem Exchange per the IT doc; if the mailbox turns
      out to live in Exchange Online, IMAP/SMTP move to outlook.office365.com /
      smtp.office365.com and only work over the corporate VPN.
    '';
  };

  config = mkIf cfg.enable {
    programs.thunderbird = {
      enable = true;
      profiles.work = {
        isDefault = true;

        settings = mkIf cfg.owaStyle {
          # Match OWA's light, vertical three-pane presentation. The card view
          # keeps sender, subject, and preview on separate lines; userChrome
          # turns the cards into OWA-like flat rows.
          "browser.theme.content-theme" = 1;
          "browser.theme.toolbar-theme" = 1;
          "mail.pane_config.dynamic" = 2;
          "mail.threadpane.cardsview.rowcount" = 3;
          "mail.threadpane.listview" = 0;
          "mail.uidensity" = 1;
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
        };

        userChrome = optionalString cfg.owaStyle ''
          /* Outlook Web Access-inspired chrome for Thunderbird's vertical mail view. */

          :root {
            color-scheme: light !important;

            --owa-blue: #0078d4;
            --owa-blue-dark: #005a9e;
            --owa-blue-pale: #c7e0f4;
            --owa-blue-subtle: #deecf9;
            --owa-canvas: #ffffff;
            --owa-sidebar: #f3f2f1;
            --owa-hover: #edebe9;
            --owa-border: #e1dfdd;
            --owa-text: #323130;
            --owa-muted: #605e5c;

            --layout-background-0: var(--owa-canvas) !important;
            --layout-background-1: var(--owa-sidebar) !important;
            --layout-background-2: var(--owa-hover) !important;
            --layout-background-3: #e1dfdd !important;
            --layout-background-4: #d2d0ce !important;
            --layout-color-0: var(--owa-text) !important;
            --layout-color-1: var(--owa-text) !important;
            --layout-color-2: var(--owa-muted) !important;
            --layout-border-0: var(--owa-border) !important;
            --layout-border-1: #d2d0ce !important;
            --selected-item-color: var(--owa-blue) !important;
            --selected-item-text-color: #ffffff !important;
            --sidebar-background-color: var(--owa-sidebar) !important;
            --sidebar-text-color: var(--owa-text) !important;
            --sidebar-highlight-background-color: var(--owa-blue-pale) !important;
            --sidebar-highlight-text-color: var(--owa-blue-dark) !important;
            --toolbar-field-focus-border-color: var(--owa-blue) !important;
            --button-border-radius: 2px !important;
            --input-text-border-radius: 2px !important;

            font-family: "Segoe UI", "Noto Sans", sans-serif !important;
          }

          /* OWA's black suite bar and pale command strip. */
          #unifiedToolbarContainer,
          #unifiedToolbar {
            background: #000000 !important;
            color: #ffffff !important;
          }

          #unifiedToolbar {
            min-height: 44px !important;
          }

          #unifiedToolbar .search-bar,
          #unifiedToolbar input {
            background: #292929 !important;
            border-color: #605e5c !important;
            color: #ffffff !important;
          }

          #tabs-toolbar,
          #tabmail-tabs {
            background: #eff6fc !important;
            color: var(--owa-text) !important;
          }

          .tabmail-tab {
            border-radius: 0 !important;
          }

          .tabmail-tab[selected="true"] .tab-background {
            background: var(--owa-canvas) !important;
            box-shadow: inset 0 2px var(--owa-blue) !important;
          }

          /* Keep the same stable proportions as OWA on wide screens. */
          @media (min-width: 1100px) {
            body.layout-vertical {
              grid-template:
                "folders folderPaneSplitter threads messagePaneSplitter message" auto
                / 15rem min-content clamp(20rem, 22vw, 27rem) min-content minmax(30rem, 1fr) !important;
            }
          }

          /* Folder rail. */
          #folderPane,
          #folderPaneHeaderBar {
            background: var(--owa-sidebar) !important;
            color: var(--owa-text) !important;
          }

          #folderPane {
            border-inline-end: 1px solid var(--owa-border) !important;
          }

          #folderPaneHeaderBar {
            min-height: 48px !important;
            padding: 6px 8px !important;
          }

          #folderPaneWriteMessage {
            background-color: var(--owa-blue) !important;
            border-color: var(--owa-blue) !important;
            border-radius: 2px !important;
            color: #ffffff !important;
          }

          #folderPaneWriteMessage:hover {
            background-color: var(--owa-blue-dark) !important;
          }

          #folderTree .container {
            border-radius: 0 !important;
            min-height: 32px !important;
            padding-inline: 12px 8px !important;
          }

          #folderTree li.selected > .container,
          #folderTree li.current > .container {
            background: var(--owa-blue-pale) !important;
            color: var(--owa-blue-dark) !important;
            box-shadow: inset 3px 0 var(--owa-blue) !important;
          }

          #folderTree li:not(.selected, .current) > .container:hover {
            background: var(--owa-hover) !important;
          }

          .folder-count-badge,
          .unread-count {
            background: transparent !important;
            color: var(--owa-blue) !important;
            font-weight: 600 !important;
          }

          /* Message list: retain the useful three-line cards but flatten them into rows. */
          #threadPane,
          #threadPane > tree-view,
          #threadTree {
            background: var(--owa-canvas) !important;
            color: var(--owa-text) !important;
          }

          .list-header-bar {
            min-height: 54px !important;
            padding-inline: 14px 8px !important;
            background: var(--owa-canvas) !important;
            border-block-end: 1px solid var(--owa-border) !important;
          }

          .list-header-title {
            font-size: 1.25rem !important;
            font-weight: 400 !important;
          }

          #threadTree[rows="thread-card"] {
            padding-block: 0 !important;
            --tree-pane-background: var(--owa-canvas) !important;
            --tree-card-background: var(--owa-canvas) !important;
            --tree-card-border: transparent !important;
            --tree-card-background-current: var(--owa-hover) !important;
            --tree-card-background-selected: var(--owa-blue-subtle) !important;
            --tree-card-background-selected-current: var(--owa-blue-pale) !important;
            --tree-card-border-hover: transparent !important;
            --tree-card-border-focus: transparent !important;
            --tree-card-border-selected: transparent !important;
          }

          #threadTree[rows="thread-card"] .card-layout > td {
            padding: 0 !important;
          }

          #threadTree[rows="thread-card"] .card-layout .card-container {
            min-height: 74px !important;
            padding: 7px 10px !important;
            background: var(--tree-card-background) !important;
            border: 0 !important;
            border-block-end: 1px solid var(--owa-border) !important;
            border-radius: 0 !important;
          }

          #threadTree[rows="thread-card"] .card-layout:is(.selected, .current) .card-container {
            background: var(--owa-blue-pale) !important;
            box-shadow: inset 3px 0 var(--owa-blue) !important;
          }

          #threadTree[rows="thread-card"] .card-layout:not(.selected, .current):hover .card-container {
            background: var(--owa-hover) !important;
          }

          #threadTree[rows="thread-card"] .sender {
            color: var(--owa-text) !important;
            font-size: 0.98rem !important;
            font-weight: 400 !important;
          }

          #threadTree[rows="thread-card"] [data-properties~="unread"] .sender,
          #threadTree[rows="thread-card"] [data-properties~="unread"] .subject {
            color: var(--owa-text) !important;
            font-weight: 600 !important;
          }

          #threadTree[rows="thread-card"] :is(.subject, .date) {
            color: var(--owa-muted) !important;
          }

          #threadTree[rows="thread-card"] .date {
            font-size: 0.82rem !important;
          }

          /* Reading pane: plain white canvas with restrained separators. */
          #messagePane,
          #messagepanebox,
          .main-header-area,
          .message-header-container,
          .message-header-extra-container {
            background: var(--owa-canvas) !important;
            color: var(--owa-text) !important;
          }

          #messagePane {
            border-inline-start: 1px solid var(--owa-border) !important;
          }

          .main-header-area {
            padding: 18px 28px 12px !important;
            border-block-end: 1px solid var(--owa-border) !important;
          }

          #expandedsubjectBox {
            font-size: 1.25rem !important;
            font-weight: 400 !important;
          }

          .message-header-view-button {
            border-radius: 2px !important;
          }

          splitter {
            background: var(--owa-border) !important;
          }
        '';
      };
    };

    accounts.email.accounts.work = {
      primary = true;
      address = cfg.address;
      userName = cfg.login;
      realName = config.custom.user.fullName;
      imap = {
        host = cfg.host;
        port = 993;
        tls.enable = true; # implicit SSL/TLS
      };
      smtp = {
        host = cfg.host;
        port = 587;
        tls = {
          enable = true;
          useStartTls = true;
        };
      };
      # Server settings are declarative; the password is not — Thunderbird
      # prompts on first connect and keeps it in its own store.
      thunderbird.enable = true;
    };
  };
}
