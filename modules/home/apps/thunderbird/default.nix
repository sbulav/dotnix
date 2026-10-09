{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.apps.thunderbird;
  calendarEnabled = cfg.calendar.enable && config.custom.security.sops.enable;
  # The mirror is a systemd user timer, so it is Linux-only by construction.
  mirrorEnabled = calendarEnabled && cfg.calendar.mirror.enable && pkgs.stdenv.isLinux;
  mirrorDir = "${config.home.homeDirectory}/${cfg.calendar.mirror.path}";
  userJs = ".thunderbird/work/user.js";
  # What Thunderbird sends with compatMode.firefox on; verified accepted by OWA.
  firefoxUserAgent = "Mozilla/5.0 (X11; Linux x86_64; rv:154.0) Gecko/20100101 Firefox/154.0";
  # Exchange names its special folders in the mailbox language (Russian) and
  # subscribes none of them over IMAP, so Thunderbird — LSUB-only by default —
  # never saw them: it made its own Trash/Archives and filed Sent and Drafts
  # under Local Folders. Exchange lacks UTF8=ACCEPT, so folder URIs carry the
  # raw modified UTF-7 mailbox names (trash_folder_name, by contrast, is UTF-8
  # and Thunderbird encodes it itself).
  imapFolder = name: "imap://${cfg.login}@${cfg.host}/${name}";
  sentFolder = imapFolder "&BB4EQgQ,BEAEMAQyBDsENQQ9BD0ESwQ1-"; # Отправленные
  draftsFolder = imapFolder "&BCcENQRABD0EPgQyBDgEOgQ4-"; # Черновики
  # Exchange's non-mail folders, which IMAP lists as empty mail folders and
  # which the server refuses to delete.
  hiddenFolders = map imapFolder [
    "&BBYEQwRABD0EMAQ7-" # Журнал
    "&BBcEMAQ0BDAERwQ4-" # Задачи
    "&BBcEMAQ8BDUEQgQ6BDg-" # Заметки
    "&BBgEQQRFBD4ENARPBEkEOAQ1-" # Исходящие
    "&BBoEMAQ7BDUEPQQ0BDAEQARM-" # Календарь
    "&BBoEPgQ9BEIEMAQ6BEIESw-" # Контакты
  ];
  # Thunderbird can only hide a folder via CSS, and a folder-pane row carries
  # neither name nor URI — only the id `<mode>-<base64(uri)>`
  # (FolderPaneUtils.makeRowID). The URIs are ASCII, so bytes are chars.
  base64 =
    s:
    let
      table = stringToCharacters "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
      bytes = map strings.charToInt (stringToCharacters s);
      len = length bytes;
      byte = i: if i < len then elemAt bytes i else 0;
      chunk =
        i:
        let
          v = byte i * 65536 + byte (i + 1) * 256 + byte (i + 2);
          pad = max 0 (i + 3 - len);
        in
        concatMapStrings (elemAt table) (
          take (4 - pad) [
            (v / 262144)
            (mod (v / 4096) 64)
            (mod (v / 64) 64)
            (mod v 64)
          ]
        )
        + fixedWidthString pad "=" "";
    in
    concatStrings (genList (k: chunk (k * 3)) ((len + 2) / 3));
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

    calendar = {
      enable = mkBoolOpt true ''
        Whether to subscribe to the published OWA calendar (read-only ICS).
        Requires `custom.security.sops`: the URL embeds a bearer token, so it
        lives in `secrets/sab/default.yaml` and is spliced into user.js at
        activation instead of being written to the store.
      '';
      secret =
        mkOpt types.str "thunderbird_calendar_url"
          "SOPS secret holding the published-calendar ICS URL.";
      name = mkOpt types.str "HH" "Display name of the calendar in consumers of the local mirror.";

      mirror = {
        enable = mkBoolOpt true ''
          Whether to mirror the published calendar into a local vdir with
          vdirsyncer, for consumers that cannot fetch it themselves. noctalia
          is the one here: its libcurl client sends `curl/N` as User-Agent,
          which the OWA endpoint rejects, and it has no UA knob. The
          `custom.desktop.addons.noctalia` module picks up any
          `accounts.calendar` account with `vdirsyncer.enable` as a vdir
          account automatically.
        '';
        path =
          mkOpt types.str ".local/share/calendars/hh"
            "Mirror directory, relative to the home directory.";
        frequency = mkOpt types.str "*:0/15" "systemd OnCalendar expression for the mirror sync.";
      };
    };
  };

  config = mkIf cfg.enable {
    programs.thunderbird = {
      enable = true;
      profiles.work = {
        isDefault = true;

        settings = mkMerge [
          {
            # Exchange's anonymous published-calendar endpoint sniffs the UA
            # and 302s anything without a browser token to errorFE.aspx
            # (httpCode=500). This makes Thunderbird send
            # "... Gecko/20100101 Firefox/N Thunderbird/N", which OWA accepts;
            # it only affects HTTP, not IMAP/SMTP.
            "general.useragent.compatMode.firefox" = true;
            "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
          }
          (mkIf cfg.owaStyle {
            # Match OWA's light, vertical three-pane presentation. The card view
            # keeps sender, subject, and preview on separate lines; userChrome
            # turns the cards into OWA-like flat rows.
            "browser.theme.content-theme" = 1;
            "browser.theme.toolbar-theme" = 1;
            "mail.pane_config.dynamic" = 2;
            "mail.threadpane.cardsview.rowcount" = 3;
            "mail.threadpane.listview" = 0;
            "mail.uidensity" = 1;
            # Group by sort, expanded (kGroupBySort | kExpandAll): with the
            # default date sort this gives OWA's "last week / older" sections.
            # Only seeds new folders; existing ones keep their stored flags.
            "mailnews.default_view_flags" = 96;
          })
        ];

        userChrome =
          concatMapStrings (uri: ''
            #folderTree li[id$="-${base64 uri}"] { display: none !important; }
          '') hiddenFolders
          + optionalString cfg.owaStyle ''
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

            /* GTK is Adwaita-dark, so the system Field colour stays dark under
               color-scheme: light while text inherits the light theme's dark
               colour — compose's To/Subject rendered dark-on-dark. Pin fields. */
            :root {
              --toolbar-field-background-color: var(--owa-canvas) !important;
              --toolbar-field-background-color-focus: var(--owa-canvas) !important;
              --toolbar-field-color: var(--owa-text) !important;
              --toolbar-field-text-color-focus: var(--owa-text) !important;
              --arrowpanel-background: var(--owa-canvas) !important;
              --arrowpanel-color: var(--owa-text) !important;
            }

            #msgSubject,
            #msgSubject:focus,
            .address-container,
            .address-container:is(:focus, :focus-within, [focused="true"]) {
              background-color: var(--owa-canvas) !important;
              color: var(--owa-text) !important;
            }

            .address-pill:not([selected], .editing, .invalid-address, .key-issue) {
              background-color: var(--owa-blue-subtle) !important;
              color: var(--owa-text) !important;
            }

            .autocomplete-richlistbox {
              background-color: var(--owa-canvas) !important;
              color: var(--owa-text) !important;
            }

            /* Outlook's blue suite bar with a white search box, and a pale command strip. */
            #unifiedToolbarContainer,
            #unifiedToolbar {
              background: var(--owa-blue) !important;
              color: #ffffff !important;
            }

            #unifiedToolbar {
              min-height: 44px !important;
            }

            #unifiedToolbar .search-bar,
            #unifiedToolbar input {
              background: var(--owa-canvas) !important;
              border-color: transparent !important;
              border-radius: 4px !important;
              color: var(--owa-text) !important;
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
              color: var(--owa-text) !important;
              font-weight: 600 !important;
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
              font-size: 1.45rem !important;
              font-weight: 300 !important;
            }

            #threadPaneFolderCountContainer {
              display: none !important;
            }

            /* OWA's "Filter" is a plain blue text link. */
            #threadPaneQuickFilterButton {
              background: transparent !important;
              border-color: transparent !important;
              color: var(--owa-blue) !important;
              font-size: 1.05rem !important;
            }

            #threadPaneQuickFilterButton:hover {
              background: var(--owa-hover) !important;
            }

            /* A link has no toggle pill; show the active filter as a tint. */
            #threadPaneQuickFilterButton::before {
              display: none !important;
            }

            #threadPaneQuickFilterButton[aria-pressed="true"] {
              background: var(--owa-blue-subtle) !important;
              font-weight: 600 !important;
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
            }

            /* Unread: OWA's blue edge and blue subject. */
            #threadTree[rows="thread-card"] .card-layout[data-properties~="unread"] .card-container {
              box-shadow: inset 3px 0 var(--owa-blue) !important;
            }

            #threadTree[rows="thread-card"] .card-layout:not(.selected, .current):hover .card-container {
              background: var(--owa-hover) !important;
            }

            /* OWA row typography: large light sender, small dark subject, muted date. */
            #threadTree[rows="thread-card"] .sender {
              color: var(--owa-text) !important;
              font-size: 1.15rem !important;
              font-weight: 300 !important;
            }

            #threadTree[rows="thread-card"] .subject {
              color: var(--owa-text) !important;
              font-size: 0.88rem !important;
              font-weight: 400 !important;
            }

            #threadTree[rows="thread-card"] .date {
              color: var(--owa-muted) !important;
              font-size: 0.8rem !important;
            }

            #threadTree[rows="thread-card"] [data-properties~="unread"] .subject {
              color: var(--owa-blue) !important;
              font-weight: 600 !important;
            }

            /* Group-by-sort headers as OWA's small blue section labels. The tree
               gives them a full card's fixed height, so pin the label to the
               bottom to read as the heading of the rows below, with the
               collapse chevron before it as in OWA. */
            #threadTree[rows="thread-card"] .card-layout[data-properties~="dummy"] .card-container {
              align-content: end !important;
              padding: 0 10px 6px 18px !important;
              border-block-end: 0 !important;
              box-shadow: none !important;
            }

            #threadTree[rows="thread-card"] .card-layout[data-properties~="dummy"] .thread-card-dynamic-row {
              grid-template: "button subject" max-content / auto 1fr !important;
              align-items: center !important;
            }

            #threadTree[rows="thread-card"] .card-layout[data-properties~="dummy"] .subject {
              color: var(--owa-blue) !important;
              font-size: 0.88rem !important;
              font-weight: 600 !important;
            }

            #threadTree[rows="thread-card"] .card-layout[data-properties~="dummy"] .sort-header-details {
              display: none !important;
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

            /* OWA puts a large light subject above the sender. */
            #headerSubjectSecurityContainer {
              order: -1 !important;
              margin-block-end: 10px !important;
            }

            #expandedsubjectBox {
              font-size: 1.6rem !important;
              font-weight: 300 !important;
            }

            #expandedfromBox {
              font-size: 1.15rem !important;
              font-weight: 300 !important;
            }

            /* One reply action plus OWA's Archive and Delete, between Reply
               and More; the rest stay on the context menu and shortcuts
               (Ctrl+L, J). The smart reply button (Reply / Reply All /
               Reply List) is never hidden. */
            :is(#hdrReplyToSenderButton, #hdrForwardButton, #hdrJunkButton) {
              display: none !important;
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
      inherit (cfg) address;
      userName = cfg.login;
      realName = config.custom.user.fullName;
      imap = {
        inherit (cfg) host;
        port = 993;
        tls.enable = true; # implicit SSL/TLS
      };
      smtp = {
        inherit (cfg) host;
        port = 587;
        tls = {
          enable = true;
          useStartTls = true;
        };
      };
      # Server settings are declarative; the password is not — Thunderbird
      # prompts on first connect and keeps it in its own store.
      thunderbird = {
        enable = true;
        settings = id: {
          "mail.server.server_${id}.using_subscription" = false;
          "mail.server.server_${id}.trash_folder_name" = "Удаленные";
        };
        # The mailbox has no Exchange archive folder, so archive goes to the
        # `Archives` Thunderbird created — flat, like OWA, instead of the
        # default per-year `Archives/<year>` subfolders, none of which ever
        # appeared on the server.
        perIdentitySettings = id: {
          "mail.identity.id_${id}.fcc_folder" = sentFolder;
          "mail.identity.id_${id}.fcc_folder_picker_mode" = "1";
          "mail.identity.id_${id}.draft_folder" = draftsFolder;
          "mail.identity.id_${id}.drafts_folder_picker_mode" = "1";
          "mail.identity.id_${id}.archive_folder" = imapFolder "Archives";
          "mail.identity.id_${id}.archive_folder_picker_mode" = "1";
          "mail.identity.id_${id}.archive_granularity" = 0;
        };
        # Thunderbird files these; an OWA server rule (outside Nix) still
        # moves Mattermost into `Notifications` before they run. Targets must
        # already exist on the server, or the move fails. Type 17 is new mail
        # (1) plus manual (16), so Tools > Run Filters on Folder applies the
        # same rules to the backlog. First match wins.
        messageFilters =
          let
            moveTo = name: folder: conditions: {
              inherit name;
              type = "17";
              action = "Move to folder";
              actionValue = imapFolder folder;
              condition = concatMapStringsSep " " (c: "OR (${c})") conditions;
            };
          in
          [
            (moveTo "Jira and Wiki" "INBOX/Jira-Wiki" [
              "from,is,jira@hh.ru"
              "from,is,confluence@hh.ru"
              "subject,begins with,[JIRA]"
              "subject,begins with,[wiki.hh.ru]"
            ])
            (moveTo "Forgejo and Sentry" "INBOX/Dev" [
              "from,is,forgejo@pyn.ru"
              "from,is,sentry@sentry.hh.ru"
            ])
            # Ahead of Meetings: news@ forwards webinar invites with an ICS.
            (moveTo "Newsletters" "INBOX/Newsletters" [
              "from,is,news@hh.ru"
              "from,is,pr_communications@hh.ru"
              "from,contains,talantix"
              "subject,contains,[MASSMAIL]"
            ])
            # Exchange marks invites with no header, only a text/calendar
            # part, so match its ICS body. Body search fetches every new
            # message before filtering, which offline sync does anyway.
            (moveTo "Meetings" "INBOX/Meetings" [
              "body,contains,BEGIN:VCALENDAR"
              "subject,contains,Готова запись встречи"
              "subject,contains,Уведомления о переадресации собрания"
            ])
          ];
      };
    };

    # Published OWA calendar. The URL is a SOPS placeholder at eval time, so
    # the store copy of user.js never carries the token: HM's generated
    # user.js is disabled as a store symlink and re-emitted as a sops
    # template at the same path, with the placeholder filled in on
    # activation. Exchange publishes ICS one-way, so mark it read-only or
    # Thunderbird PUTs on every edit and errors.
    accounts.calendar.accounts.work = mkIf calendarEnabled {
      remote = {
        type = "http";
        url = config.sops.placeholder.${cfg.calendar.secret};
      };
      thunderbird = {
        enable = true;
        readOnly = true;
        settings = id: {
          # HM hands `settings` the bare hash; its own keys are `calendar_${id}`.
          "calendar.registry.calendar_${id}.refreshInterval" = 15;
        };
      };
    };

    # Local vdir mirror of the same ICS. A second HM account rather than
    # vdirsyncer on `work`: HM rejects `url` and `urlCommand` on one storage,
    # and Thunderbird needs the URL inline while vdirsyncer must read it from
    # the decrypted secret at run time so the store copy of its config stays
    # token-free. The remote is one-way, so the local side is a pure replica.
    accounts.calendar.basePath = mkDefault ".local/share/calendars";
    accounts.calendar.accounts.hh = mkIf mirrorEnabled {
      remote.type = "http";
      local.path = mirrorDir;
      vdirsyncer = {
        enable = true;
        urlCommand = [
          "${pkgs.coreutils}/bin/cat"
          config.sops.secrets.${cfg.calendar.secret}.path
        ];
        userAgent = firefoxUserAgent;
        conflictResolution = "remote wins";
      };
    };

    programs.vdirsyncer.enable = mkIf mirrorEnabled true;

    services.vdirsyncer = mkIf mirrorEnabled {
      enable = true;
      frequency = cfg.calendar.mirror.frequency;
    };

    # HM's unit runs only `metasync` + `sync`, and vdirsyncer refuses to sync
    # a pair it has never discovered — even with collections = null — so a
    # fresh home would fail on every tick. discover is idempotent.
    systemd.user.services.vdirsyncer.Service.ExecStart = mkIf mirrorEnabled (mkBefore [
      "${config.services.vdirsyncer.package}/bin/vdirsyncer discover"
    ]);

    # vdir collection metadata: readers (noctalia, khal) show this instead of
    # the directory name. vdirsyncer only touches *.ics here, so it survives.
    home.file."${cfg.calendar.mirror.path}/displayname" = mkIf mirrorEnabled {
      text = cfg.calendar.name;
    };

    custom.security.sops.secrets.${cfg.calendar.secret} = mkIf calendarEnabled { };

    home.file.${userJs}.enable = mkIf calendarEnabled false;

    sops.templates."thunderbird-work-user.js" = mkIf calendarEnabled {
      content = config.home.file.${userJs}.text;
      path = "${config.home.homeDirectory}/${userJs}";
      mode = "0600";
    };
  };
}
