{
  options,
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    types
    mkIf
    mkOption
    mkEnableOption
    mapAttrsToList
    concatMapStringsSep
    concatStringsSep
    optionalString
    optionals
    ;
  inherit (lib.custom) mkBoolOpt mkOpt;

  cfg = config.custom.desktop.hyprland;

  # ---------- Lua helpers -----------------------------------------------------

  # "foo" → "\"foo\""
  luaStr = s: "\"" + lib.replaceStrings [ "\\" "\"" ] [ "\\\\" "\\\"" ] s + "\"";

  # Parse "title:something" or "initialClass:foo" → { field, pattern }
  parseMatch =
    app:
    let
      parts = lib.splitString ":" app;
      hasField =
        builtins.length parts > 1
        && builtins.elem (builtins.elemAt parts 0) [
          "title"
          "initialTitle"
          "initialClass"
        ];
      rawField = if hasField then builtins.elemAt parts 0 else "class";
      pattern = if hasField then lib.concatStringsSep ":" (builtins.tail parts) else app;
      # Lua API uses snake_case
      field =
        {
          "title" = "title";
          "initialTitle" = "initial_title";
          "initialClass" = "initial_class";
          "class" = "class";
        }
        .${rawField};
      isTitleLike = rawField == "title" || rawField == "initialTitle";
      regex = if isTitleLike then "^(.*${pattern}.*)$" else "^(${pattern})$";
    in
    {
      inherit field regex;
    };

  mkWorkspaceRules =
    assignments:
    concatMapStringsSep "\n" (
      ws:
      let
        apps = assignments.${ws};
        mkRule =
          app:
          let
            m = parseMatch app;
          in
          "hl.window_rule({ match = { ${m.field} = ${luaStr m.regex} }, workspace = ${luaStr "${ws} silent"} })";
      in
      concatMapStringsSep "\n" mkRule apps
    ) (builtins.attrNames assignments);

  # Parse a monitor string like ",preferred,auto,auto" or
  # "DP-1,1920x1080@60,0x0,1" into hl.monitor(...) call.
  # `scale` is rendered as a Lua number; non-numeric values like "auto"
  # collapse to 1 (Hyprland's documented fallback).
  mkMonitor =
    s:
    let
      p = lib.splitString "," s;
      get = i: if builtins.length p > i then builtins.elemAt p i else "";
      rawScale = get 3;
      scaleLua =
        if rawScale == "" || rawScale == "auto" then
          "1"
        else if builtins.match "[0-9]+(\\.[0-9]+)?" rawScale != null then
          rawScale
        else
          luaStr rawScale;
    in
    "hl.monitor({ output = ${luaStr (get 0)}, mode = ${luaStr (get 1)}, position = ${luaStr (get 2)}, scale = ${scaleLua} })";

  mkWorkspaceMonitorBindings =
    bindings:
    mapAttrsToList (
      ws: mon: "hl.workspace_rule({ workspace = ${luaStr ws}, monitor = ${luaStr mon} })"
    ) bindings;

  # Translate a hyprlang-style action into a Lua dispatcher expression.
  # Examples:
  #   "exec, wezterm"           → hl.dsp.exec_cmd("wezterm")
  #   "killactive,"             → hl.dsp.window.close()
  #   "exit"                    → hl.dsp.exit()
  #   "fullscreen,"             → hl.dsp.window.fullscreen()
  #   "togglefloating,"         → hl.dsp.window.float()
  #   "pseudo,"                 → hl.dsp.window.pseudo()
  #   "layoutmsg, togglesplit"  → hl.dsp.layout("togglesplit")
  translateAction =
    action:
    let
      parts = map lib.trim (lib.splitString "," action);
      verb = builtins.elemAt parts 0;
      arg = if builtins.length parts > 1 then concatStringsSep "," (builtins.tail parts) else "";
      argTrim = lib.trim arg;
    in
    if verb == "exec" then
      "hl.dsp.exec_cmd(${luaStr argTrim})"
    else if verb == "killactive" then
      "hl.dsp.window.close()"
    else if verb == "exit" then
      "hl.dsp.exit()"
    else if verb == "fullscreen" then
      "hl.dsp.window.fullscreen({ action = \"toggle\" })"
    else if verb == "togglefloating" then
      "hl.dsp.window.float({ action = \"toggle\" })"
    else if verb == "pseudo" then
      "hl.dsp.window.pseudo({ action = \"toggle\" })"
    else if verb == "layoutmsg" then
      "hl.dsp.layout(${luaStr argTrim})"
    else
      throw "translateAction: unsupported verb '${verb}' in '${action}'";

  mkBind =
    mainMod: keySpec: action:
    let
      keyParts = lib.splitString " " keySpec;
      hasModifiers = builtins.length keyParts > 1;
      extraMods = if hasModifiers then lib.init keyParts else [ ];
      actualKey = if hasModifiers then lib.last keyParts else keySpec;
      keyStr = concatStringsSep " + " ([ mainMod ] ++ extraMods ++ [ actualKey ]);
    in
    "hl.bind(${luaStr keyStr}, ${translateAction action})";

  mkKeybindings =
    kb:
    let
      mainMod = kb.mainMod;

      appBindings =
        optionalString (kb.terminal != null) ''
          ${mkBind mainMod kb.terminal "exec, wezterm"}
        ''
        + optionalString (kb.browser != null) ''
          ${mkBind mainMod kb.browser "exec, firefox"}
        ''
        + optionalString (kb.launcher != null) ''
          ${mkBind mainMod kb.launcher "exec, rofi -show drun"}
        ''
        + optionalString (kb.clipboard != null) ''
          ${mkBind mainMod kb.clipboard
            "exec, rofi -show clip -theme-str 'listview { columns: 1; fixed-columns: true; }'"
          }
        ''
        + optionalString (kb.passwords != null) ''
          ${mkBind mainMod kb.passwords "exec, rofi-rbw"}
        ''
        + optionalString (kb.search != null) ''
          ${mkBind mainMod kb.search
            ''exec, rofi -dmenu -p "Search" | xargs -I{} xdg-open "https://www.google.com/search?q={}" && hyprctl dispatch focuswindow firefox''
          }
        ''
        + optionalString (kb.woomer != null) ''
          ${mkBind mainMod kb.woomer "exec, woomer"}
        ''
        + optionalString (kb.lock != null) ''
          ${mkBind mainMod "SHIFT ${kb.lock}" "exec, swaylock"}
        ''
        + optionalString (kb.logout != null) ''
          ${mkBind mainMod "SHIFT ${kb.logout}" "exec, wlogout"}
        '';

      windowBindings =
        optionalString (kb.kill != null) ''
          ${mkBind mainMod kb.kill "killactive,"}
        ''
        + optionalString (kb.exit != null) ''
          ${mkBind mainMod "SHIFT ${kb.exit}" "exit"}
        ''
        + optionalString (kb.fullscreen != null) ''
          ${mkBind mainMod kb.fullscreen "fullscreen,"}
        ''
        + optionalString (kb.floating != null && kb.paste == null) ''
          ${mkBind mainMod kb.floating "togglefloating,"}
        ''
        + optionalString (kb.pseudo != null) ''
          ${mkBind mainMod kb.pseudo "pseudo,"}
        ''
        + optionalString (kb.split != null) ''
          ${mkBind mainMod kb.split "layoutmsg, togglesplit"}
        '';

      copyPasteBindings = optionalString (kb.floating != null && kb.paste != null) ''
        ${mkBind mainMod "SHIFT ${kb.floating}" "togglefloating,"}
      '';

      # `extra` entries are now expected to be full Lua statements.
      extraBindings = concatStringsSep "\n" kb.extra;

      screenshotCfg = config.custom.desktop.addons.screenshot;
      sc = screenshotCfg.commands;
      hasAnnotate = screenshotCfg.enable && screenshotCfg.annotator != "none";
      mkPrintBind = modKey: cmd: "hl.bind(${luaStr modKey}, hl.dsp.exec_cmd(${luaStr cmd}))";
      screenshotBindings =
        if !screenshotCfg.enable then
          ""
        else
          concatStringsSep "\n" (
            [
              (mkPrintBind "Print" sc.region.clipboard)
              (mkPrintBind "SHIFT + Print" sc.region.file)
              (mkPrintBind "CONTROL + Print" sc.window.clipboard)
              (mkPrintBind "CONTROL + SHIFT + Print" sc.window.file)
              (mkPrintBind "SUPER + Print" sc.screen.file)
              (mkPrintBind "SUPER + SHIFT + Print" sc.screen.clipboard)
            ]
            ++ optionals hasAnnotate [
              (mkPrintBind "ALT + Print" sc.region.annotate)
            ]
          );
    in
    appBindings + windowBindings + copyPasteBindings + extraBindings + "\n" + screenshotBindings;
in
{
  options.custom.desktop.hyprland = {
    enable = mkBoolOpt false "Whether or not to install Hyprland and dependencies.";

    monitors = mkOpt (types.listOf types.str) [
      ",preferred,auto,auto"
    ] "Monitor configuration strings (output,mode,position,scale)";

    workspaces = {
      assignments = mkOpt (types.attrsOf (types.listOf types.str)) {
        "1" = [
          "wezterm"
          "org.wezfurlong.wezterm"
        ];
        "2" = [ "firefox" ];
        "4" = [
          "org.telegram.desktop"
          "zoom"
        ];
        "5" = [
          "mpv"
          "vlc"
          "mpdevil"
        ];
        "6" = [ "virt-manager" ];
        "7" = [
          "Slack"
          "initialTitle:obsidian - Obsidian"
          "ktalk"
        ];
      } "Workspace to application class mappings";

      monitorBindings =
        mkOpt (types.attrsOf types.str) { }
          "Workspace to monitor bindings (workspace ID -> monitor name)";
    };

    keybindings = {
      mainMod = mkOpt types.str "SUPER" "Main modifier key";

      terminal = mkOpt (types.nullOr types.str) "X" "Launch terminal keybinding";
      browser = mkOpt (types.nullOr types.str) "B" "Launch browser keybinding";
      launcher = mkOpt (types.nullOr types.str) "R" "App launcher keybinding";
      clipboard = mkOpt (types.nullOr types.str) "C" "Clipboard manager keybinding";
      passwords = mkOpt (types.nullOr types.str) "P" "Password manager keybinding";
      search = mkOpt (types.nullOr types.str) "Z" "Web search keybinding";
      woomer = mkOpt (types.nullOr types.str) null "Woomer (Wayland zoomer) keybinding";
      lock = mkOpt (types.nullOr types.str) "L" "Lock screen keybinding";
      logout = mkOpt (types.nullOr types.str) "P" "Logout menu keybinding";

      kill = mkOpt (types.nullOr types.str) "Q" "Kill active window keybinding";
      exit = mkOpt (types.nullOr types.str) "M" "Exit Hyprland keybinding";
      fullscreen = mkOpt (types.nullOr types.str) "F" "Toggle fullscreen keybinding";
      floating = mkOpt (types.nullOr types.str) "V" "Toggle floating keybinding";
      pseudo = mkOpt (types.nullOr types.str) "U" "Pseudo-tile keybinding";
      split = mkOpt (types.nullOr types.str) "J" "Toggle split keybinding";

      copy = mkOpt (types.nullOr types.str) null "Copy to clipboard keybinding";
      paste = mkOpt (types.nullOr types.str) null "Paste from clipboard keybinding";

      extra = mkOpt (types.listOf types.str) [ ] "Additional custom keybindings (raw Lua statements)";
    };
  };

  config = mkIf cfg.enable {
    home = {
      packages = with pkgs; [
        brightnessctl
        wtype
        hyprpicker
      ];

      # Hyprland 0.55 reads hyprland.lua. If a session ever starts before
      # home-manager has linked the lua file, Hyprland writes a STUB
      # hyprland.conf in its place and keeps using it. Wipe that stub on
      # activation so a subsequent reload picks up the real config.
      activation.removeHyprlandStubConf = {
        after = [ "writeBoundary" ];
        before = [ ];
        data = ''
          stub="$HOME/.config/hypr/hyprland.conf"
          if [ -f "$stub" ] && [ ! -L "$stub" ] && grep -q "STUB" "$stub" 2>/dev/null; then
            $DRY_RUN_CMD rm -f "$stub"
          fi
        '';
      };
    };

    wayland.windowManager.hyprland = {
      enable = true;
      systemd.enable = false;
      xwayland.enable = true;
      configType = "lua";

      # All directives are emitted via extraConfig (Lua); `settings` would
      # need each top-level key to map cleanly onto an `hl.<key>(...)` call,
      # which doesn't fit our gradient/list shapes — easier to render raw.
      settings = { };

      extraConfig =
        let
          c = config.custom.theme.colors;
          themeAndGeneral = ''
            hl.config({
              general = {
                gaps_in = 5,
                gaps_out = 5,
                border_size = 2,
                ["col.active_border"] = { colors = { "rgba(${c.cyan}ff)", "rgba(${c.pink}ff)" }, angle = 45 },
                ["col.inactive_border"] = "rgba(${c.separator}aa)",
                layout = "dwindle",
              },
            })
          '';
          monitors = concatStringsSep "\n" (map mkMonitor cfg.monitors);
          monitorBindings = concatStringsSep "\n" (mkWorkspaceMonitorBindings cfg.workspaces.monitorBindings);
        in
        ''
          ${builtins.readFile ./hyprland.lua}

          -- Theme-driven general block
          ${themeAndGeneral}

          -- Monitors
          ${monitors}

          -- Workspace ↔ monitor bindings
          ${monitorBindings}

          -- Workspace assignments (windows → workspaces)
          ${mkWorkspaceRules cfg.workspaces.assignments}

          -- Keybindings
          ${mkKeybindings cfg.keybindings}
        '';
    };
  };
}
