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
    optionalString
    ;
  inherit (lib.custom) mkBoolOpt mkOpt;

  cfg = config.custom.desktop.hyprland;

  mkWorkspaceRules =
    assignments:
    concatMapStringsSep "\n" (
      ws:
      let
        apps = assignments.${ws};
      in
      concatMapStringsSep "\n" (app: "windowrulev2 = workspace ${ws} silent, class:^(${app})$") apps
    ) (builtins.attrNames assignments);

  mkWorkspaceMonitorBindings = bindings: mapAttrsToList (ws: mon: "${ws},monitor:${mon}") bindings;

  mkBind =
    mainMod: key: action:
    let
      parts = lib.splitString " " key;
      hasModifiers = builtins.length parts > 1;
      mods = if hasModifiers then "${mainMod} ${lib.concatStringsSep " " (lib.init parts)}" else mainMod;
      actualKey = if hasModifiers then lib.last parts else key;
    in
    "bind = ${mods}, ${actualKey}, ${action}";

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
          ${mkBind mainMod kb.split "togglesplit,"}
        '';

      copyPasteBindings =
        # optionalString (kb.copy != null) ''
        #   ${mkBind mainMod kb.copy "exec, wl-copy"}
        # ''
        # + optionalString (kb.paste != null) ''
        #   ${mkBind mainMod kb.paste "exec, cliphist list | head -n 1 | cliphist decode | wl-copy && wtype -M ctrl v -m ctrl"}
        # ''
        # + optionalString (kb.floating != null && kb.paste != null) ''
        optionalString (kb.floating != null && kb.paste != null) ''
          ${mkBind mainMod "SHIFT ${kb.floating}" "togglefloating,"}
        '';

      extraBindings = concatMapStringsSep "\n" (binding: "bind = ${binding}") kb.extra;
    in
    appBindings + windowBindings + copyPasteBindings + extraBindings;
in
{
  options.custom.desktop.hyprland = {
    enable = mkBoolOpt false "Whether or not to install Hyprland and dependencies.";

    monitors = mkOpt (types.listOf types.str) [
      ",preferred,auto,auto"
    ] "Monitor configuration strings";

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
          "obsidian"
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

      extra = mkOpt (types.listOf types.str) [ ] "Additional custom keybindings";
    };
  };

  config = mkIf cfg.enable {
    home = {
      packages = with pkgs; [
        brightnessctl
        wtype
        hyprpicker
      ];
    };

    wayland.windowManager.hyprland = {
      enable = true;
      systemd.enable = false;
      xwayland.enable = true;

      settings = {
        monitor = cfg.monitors;

        workspace = mkWorkspaceMonitorBindings cfg.workspaces.monitorBindings;

        cursor = {
          enable_hyprcursor = true;
          sync_gsettings_theme = true;
        };
      };

      extraConfig = ''
        ${builtins.readFile ./hyprland.conf}

        ${mkWorkspaceRules cfg.workspaces.assignments}

        ${mkKeybindings cfg.keybindings}
      '';
    };
  };
}
