{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.desktop.addons."wlr-which-key";
  yamlFormat = pkgs.formats.yaml { };

  defaultMenu = [
    {
      key = "a";
      desc = "Apps";
      submenu = [
        {
          key = "t";
          desc = "Terminal";
          cmd = "wezterm";
        }
        {
          key = "b";
          desc = "Browser";
          cmd = "firefox";
        }
        {
          key = "r";
          desc = "App Launcher";
          cmd = "rofi -show drun";
        }
        {
          key = "c";
          desc = "Clipboard";
          cmd = "rofi -show clip -theme-str 'listview { columns: 1; fixed-columns: true; }'";
        }
        {
          key = "p";
          desc = "Passwords";
          cmd = "rofi-rbw";
        }
        {
          key = "z";
          desc = "Web Search";
          cmd = ''rofi -dmenu -p "Search" | xargs -I{} xdg-open "https://www.google.com/search?q={}"'';
        }
      ];
    }
    {
      key = "t";
      desc = "Wezterm";
      submenu = [
        {
          key = "o";
          desc = "Quick Select";
          cmd = ''notify-send -t 4000 "Wezterm: Quick Select" "Ctrl-B, o\nHighlights: URLs, paths, emails, IPs, git hashes, UUIDs\nType label to copy match to clipboard"'';
        }
        {
          key = "x";
          desc = "Copy Mode";
          cmd = ''notify-send -t 4000 "Wezterm: Copy Mode" "Ctrl-B, x\nVim-like navigation: h/j/k/l, w/b, 0/$\nv = start selection, y = copy\n/ = search, n/N = next/prev match\nEsc or q = exit"'';
        }
        {
          key = "f";
          desc = "Search";
          cmd = ''notify-send -t 4000 "Wezterm: Search" "Ctrl-Shift-F (default)\nType pattern, Enter to search\nCtrl-R = cycle match type (Regex/Case)\nCtrl-N/Ctrl-P = next/prev match\nEsc = close"'';
        }
        {
          key = "s";
          desc = "Split Vertical";
          cmd = ''notify-send -t 3000 "Wezterm: Split" "Ctrl-B, - or Ctrl-B, s = vertical\nCtrl-B, \\ or Ctrl-B, v = horizontal\nAlt-= / Alt-- also work"'';
        }
        {
          key = "z";
          desc = "Zoom Pane";
          cmd = ''notify-send -t 3000 "Wezterm: Zoom" "Ctrl-B, z = toggle pane zoom"'';
        }
        {
          key = "n";
          desc = "Navigation";
          cmd = ''notify-send -t 4000 "Wezterm: Navigation" "Ctrl-B, h/j/k/l = focus pane\nCtrl-B, Shift+H/J/K/L = resize pane\nCtrl-B, n/p = next/prev tab\nCtrl-B, 1-9 = go to tab\nCtrl-B, c = new tab\nCtrl-B, d = close pane"'';
        }
      ];
    }
    {
      key = "w";
      desc = "Window";
      submenu = [
        {
          key = "q";
          desc = "Kill Active";
          cmd = "hyprctl dispatch killactive";
        }
        {
          key = "f";
          desc = "Fullscreen";
          cmd = "hyprctl dispatch fullscreen";
        }
        {
          key = "v";
          desc = "Toggle Floating";
          cmd = "hyprctl dispatch togglefloating";
        }
        {
          key = "u";
          desc = "Pseudo-tile";
          cmd = "hyprctl dispatch pseudo";
        }
        {
          key = "j";
          desc = "Toggle Split";
          cmd = "hyprctl dispatch togglesplit";
        }
        {
          key = "h";
          desc = "Focus Left";
          cmd = "hyprctl dispatch movefocus l";
        }
        {
          key = "l";
          desc = "Focus Right";
          cmd = "hyprctl dispatch movefocus r";
        }
        {
          key = "k";
          desc = "Focus Up";
          cmd = "hyprctl dispatch movefocus u";
        }
      ];
    }
    {
      key = "s";
      desc = "Screenshot";
      submenu = [
        {
          key = "r";
          desc = "Region to File";
          cmd = ''grim -g "$(slurp)" ~/Pictures/Screenshots/$(date +\'ss_%s.png\')'';
        }
        {
          key = "c";
          desc = "Region to Clipboard";
          cmd = ''grim -g "$(slurp)" - | wl-copy'';
        }
        {
          key = "f";
          desc = "Full Screen";
          cmd = "grim ~/Pictures/Screenshots/$(date +\'ss_%s.png\')";
        }
      ];
    }
    {
      key = "m";
      desc = "Media";
      submenu = [
        {
          key = "p";
          desc = "Play/Pause";
          cmd = "playerctl play-pause";
        }
        {
          key = "n";
          desc = "Next Track";
          cmd = "playerctl next";
        }
        {
          key = "b";
          desc = "Previous Track";
          cmd = "playerctl previous";
        }
      ];
    }
    {
      key = "r";
      desc = "Ripgrep";
      submenu = [
        {
          key = "i";
          desc = "Case Insensitive";
          cmd = ''notify-send -t 4000 "rg: Case Insensitive" "rg -i pattern\nrg -s pattern  (smart case)"'';
        }
        {
          key = "w";
          desc = "Whole Word";
          cmd = ''notify-send -t 3000 "rg: Whole Word" "rg -w pattern"'';
        }
        {
          key = "l";
          desc = "List Files Only";
          cmd = ''notify-send -t 4000 "rg: List Files" "rg -l pattern        (files with matches)\nrg --files-without-match pattern  (files without)"'';
        }
        {
          key = "t";
          desc = "File Type Filter";
          cmd = ''notify-send -t 4000 "rg: File Type" "rg -t py pattern   (only Python)\nrg -T py pattern   (exclude Python)\nrg --type-list      (show all types)"'';
        }
        {
          key = "g";
          desc = "Glob Filter";
          cmd = ''notify-send -t 4000 "rg: Glob" "rg pattern -g '*.py'    (only .py files)\nrg pattern -g '!*.py'   (exclude .py)\nCan use -g multiple times"'';
        }
        {
          key = "F";
          desc = "Literal (No Regex)";
          cmd = ''notify-send -t 3000 "rg: Literal Search" "rg -F '(exact match)'\nNo regex interpretation"'';
        }
        {
          key = "c";
          desc = "Count Matches";
          cmd = ''notify-send -t 4000 "rg: Count" "rg --count pattern         (matching lines per file)\nrg --count-matches pattern (total matches per file)\nrg pattern --stats         (full search statistics)"'';
        }
        {
          key = "v";
          desc = "Inverse Search";
          cmd = ''notify-send -t 3000 "rg: Inverse" "rg -v pattern\nShow lines NOT matching pattern"'';
        }
      ];
    }
    {
      key = "f";
      desc = "fd";
      submenu = [
        {
          key = "e";
          desc = "By Extension";
          cmd = ''notify-send -t 3000 "fd: Extension" "fd -e txt\nfd -e py pattern"'';
        }
        {
          key = "g";
          desc = "Glob (Exact Name)";
          cmd = ''notify-send -t 3000 "fd: Glob" "fd -g 'name.ext'\nfd -g '*.py' path/"'';
        }
        {
          key = "H";
          desc = "Include Hidden";
          cmd = ''notify-send -t 3000 "fd: Hidden Files" "fd -H pattern\nfd --hidden --no-ignore pattern"'';
        }
        {
          key = "E";
          desc = "Exclude";
          cmd = ''notify-send -t 3000 "fd: Exclude" "fd -E node_modules pattern\nfd -E '*.pyc' pattern"'';
        }
        {
          key = "x";
          desc = "Exec on Results";
          cmd = ''notify-send -t 4000 "fd: Exec" "fd pattern --exec command\nfd -e jpg --exec convert {} {.}.png"'';
        }
        {
          key = "r";
          desc = "Regex Search";
          cmd = ''notify-send -t 4000 "fd: Regex" "fd '^foo'           (starts with foo)\nfd 'test.*\\.py$'   (regex match)\nfd pattern path/    (search in dir)"'';
        }
      ];
    }
    {
      key = "p";
      desc = "Power";
      submenu = [
        {
          key = "l";
          desc = "Lock Screen";
          cmd = "swaylock";
        }
        {
          key = "e";
          desc = "Logout";
          cmd = "wlogout";
        }
        {
          key = "s";
          desc = "Suspend";
          cmd = "systemctl suspend";
        }
        {
          key = "r";
          desc = "Reboot";
          cmd = "systemctl reboot";
        }
        {
          key = "o";
          desc = "Power Off";
          cmd = "systemctl poweroff";
        }
      ];
    }
  ];

  configFile = yamlFormat.generate "wlr-which-key-config.yaml" {
    font = cfg.font;
    background = cfg.background;
    color = cfg.color;
    border = cfg.border;
    separator = cfg.separator;
    border_width = cfg.borderWidth;
    corner_r = cfg.cornerRadius;
    padding = cfg.padding;
    rows_per_column = cfg.rowsPerColumn;
    column_padding = cfg.columnPadding;
    anchor = cfg.anchor;
    margin_right = cfg.marginRight;
    margin_bottom = cfg.marginBottom;
    margin_left = cfg.marginLeft;
    margin_top = cfg.marginTop;
    menu = cfg.menu;
  };
in
{
  options.custom.desktop.addons."wlr-which-key" = with types; {
    enable = mkBoolOpt false "Whether to enable wlr-which-key cheatsheet.";

    font = mkOpt str "CaskaydiaCove Nerd Font Mono 12" "Font for the which-key popup.";
    background = mkOpt str "#0d1117d0" "Background color.";
    color = mkOpt str "#c9d1d9" "Text color.";
    border = mkOpt str "#33ccff" "Border color.";
    separator = mkOpt str " -> " "Separator between key and description.";
    borderWidth = mkOpt int 2 "Border width in pixels.";
    cornerRadius = mkOpt int 10 "Corner radius in pixels.";
    padding = mkOpt int 12 "Padding in pixels.";
    rowsPerColumn = mkOpt int 8 "Maximum rows per column.";
    columnPadding = mkOpt int 25 "Padding between columns.";
    anchor = mkOpt str "center" "Anchor position.";
    marginRight = mkOpt int 0 "Right margin.";
    marginBottom = mkOpt int 0 "Bottom margin.";
    marginLeft = mkOpt int 0 "Left margin.";
    marginTop = mkOpt int 0 "Top margin.";

    menu = mkOpt (yamlFormat.type) defaultMenu "Menu structure for wlr-which-key.";
  };

  config = mkIf cfg.enable {
    home.packages = [
      pkgs.wlr-which-key
      pkgs.libnotify
    ];

    xdg.configFile."wlr-which-key/config.yaml".source = configFile;
  };
}
