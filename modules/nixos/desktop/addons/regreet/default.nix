{
  options,
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.desktop.addons.regreet;
  wallpaper = options.system.wallpaper.value;
  dbus-run-session = lib.getExe' pkgs.dbus "dbus-run-session";
  hyprland = lib.getExe config.programs.hyprland.package;
  hyprland-conf = pkgs.writeText "greetd-hyprland.conf" ''
    bind = SUPER SHIFT, E, killactive,
    misc {
        disable_hyprland_logo = true
    }
    animations {
        enabled = false
    }
    exec-once = ${lib.getExe config.programs.regreet.package}; hyprctl dispatch exit
  '';
in
{
  options.custom.desktop.addons.regreet = with types; {
    enable = mkBoolOpt false "Whether to enable the regreet display manager";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      # theme packages
      (catppuccin-gtk.override {
        accents = [ "mauve" ];
        size = "compact";
        variant = "mocha";
      })
      bibata-cursors
      papirus-icon-theme
    ];
    programs.regreet = {
      enable = true;

      cursorTheme.name = "Bibata-Modern-Classic";
      font.name = "FiraCode Nerd Font Regular";
      font.size = 12;
      iconTheme.name = "Papirus-Dark";
      theme.name = "Catppuccin-Mocha-Compact-Mauve-dark";

      settings = {
        env = {
          STATE_DIR = "/var/cache/regreet";
        };

        background = {
          path = wallpaper;
          fit = "Cover";
        };
      };
      # Lightweight cyberdream look (flat, neon accents, no bubbles)
      extraCss = ''
        /* ReGreet – Cyberdream (readable dark, GTK4-safe, optimized)
           Goals: high contrast text, dark controls, subtle neon accents. */

        /* ---------- Palette ---------- */
        @define-color cd-bg         #0f1113;
        @define-color cd-bg-ov      rgba(15,17,19,0.55);
        @define-color cd-surface    #191d22;
        @define-color cd-surface-2  #1f252b;
        @define-color cd-border     #2b323a;

        @define-color cd-text       #e6edf3;
        @define-color cd-subtext    #c1cad6;
        @define-color cd-muted      #97a4b6;

        @define-color cd-blue       #5ea1ff;
        @define-color cd-cyan       #5ef1ff;
        @define-color cd-green      #78f093;
        @define-color cd-yellow     #ffd76b;
        @define-color cd-red        #ff6b82;
        @define-color cd-magenta    #ff5ef1;

        /* ---------- Base window ---------- */
        window, window.background {
          /* readable overlay on top of your wallpaper */
          background-color: @cd-bg-ov;
          color: @cd-text;
        }

        label, .label { color: @cd-text; }
        .separator, separator { background-color: alpha(@cd-border, 0.6); min-height: 1px; min-width: 1px; }

        /* ---------- Inputs ---------- */
        entry {
          background: @cd-surface;
          color: @cd-text;
          border: 1px solid @cd-border;
          border-radius: 12px;
          padding: 10px 12px;
          min-height: 34px;
          background-clip: padding-box;
        }
        entry:hover { background: @cd-surface-2; }
        entry:focus {
          border-color: @cd-blue;
          box-shadow: 0 0 0 3px alpha(@cd-blue, 0.22);
        }

        /* Placeholder (GTK4) */
        entry text placeholder { color: @cd-muted; }

        /* Selection inside entries */
        entry text selection { background-color: @cd-blue; color: #0b0d0e; }

        /* Password entry dots readable */
        entry password { color: @cd-text; }

        /* ---------- Buttons ---------- */
        button {
          background: @cd-surface;
          color: @cd-text;
          border: 1px solid @cd-border;
          border-radius: 12px;
          padding: 8px 14px;
          background-clip: padding-box;
        }
        button:hover { background: @cd-surface-2; }
        button:focus {
          border-color: @cd-blue;
          box-shadow: 0 0 0 3px alpha(@cd-blue, 0.22);
        }
        button:checked,
        button:active {
          background: alpha(@cd-blue, 0.18);
          border-color: @cd-blue;
        }

        /* Destructive variant */
        button.destructive-action { border-color: @cd-red; }
        button.destructive-action:active,
        button.destructive-action:checked { background: alpha(@cd-red, 0.16); }

        /* ---------- Menus / combobox / session selector (closed widgets) ---------- */
        menubutton,
        combobox,
        dropdown,                 /* GtkDropDown closed field */
        dropdown > *,
        dropdown > button,
        dropdown > box {
          background: @cd-surface;
          color: @cd-text;
          border: 1px solid @cd-border;
          border-radius: 10px;
          background-clip: padding-box;
        }
        menubutton:hover,
        combobox:hover,
        dropdown:hover { background: @cd-surface-2; }
        menubutton image, combobox arrow, combobox image, dropdown arrow, dropdown image { color: @cd-text; }

        /* ---------- Toggles / checks ---------- */
        checkbutton, radiobutton { color: @cd-text; }
        checkbutton:hover, radiobutton:hover { color: @cd-subtext; }
        check, radio {
          background: @cd-surface;
          border: 1px solid @cd-border;
        }
        check:checked, radio:checked {
          background: alpha(@cd-blue, 0.22);
          border-color: @cd-blue;
        }

        /* ---------- Titles / headers / misc ---------- */
        .headerbar, .titlebar, .large-label { color: @cd-text; background: transparent; font-weight: 600; }
        .dim-label, .hint, .subtitle { color: @cd-subtext; }
        .error, .warning { color: @cd-red; font-weight: 600; }

        /* ---------- Keyboard focus ring (container-level) ---------- */
        :focus-within { outline: 2px solid alpha(@cd-cyan, 0.35); outline-offset: 2px; }

        /* ---------- Flatten themed “cards” so wallpaper shows through ---------- */
        /* make generic containers transparent without touching interactive controls */
        window > *,
        box, frame, stack, viewport, scrolledwindow, .frame, .card, .content, .dialog {
          background: transparent;
          box-shadow: none;
          border: none;
        }

        /* keep interactive surfaces dark (already defined above) */
        entry, button, menubutton, combobox, dropdown, menu, popover, tooltip { background-clip: padding-box; }

        /* ======================================================================= */
        /*                      DARK POPOVERS + DROPDOWNS (GTK4)                   */
        /* ======================================================================= */
        /* Popover windows (menus, dropdown popups, etc.) */
        popover,
        popover.background,
        menu, .menu {
          background: @cd-surface !important;
          color: @cd-text !important;
          border: 1px solid @cd-border !important;
          border-radius: 12px !important;
          box-shadow: none !important;
        }

        /* Everything inside inherits dark surface */
        popover *,
        popover.background * {
          background: @cd-surface !important;
          color: @cd-text !important;
        }

        /* Inner containers that often reset to white */
        popover > contents,
        popover contents,
        popover box,
        popover scrolledwindow,
        popover viewport,
        popover .view,
        popover list,
        popover listview,
        popover flowbox {
          background: @cd-surface !important;
          color: @cd-text !important;
        }

        /* Rows / items */
        popover list row,
        popover listview row,
        menuitem, modelbutton {
          background: transparent !important;
          color: @cd-text !important;
        }

        /* Hover / active / selected */
        popover list row:hover,
        popover listview row:hover,
        menuitem:hover,
        modelbutton:hover { background: @cd-surface-2 !important; }

        popover list row:selected,
        popover listview row:selected,
        menuitem:active, menuitem:checked,
        modelbutton:active, modelbutton:checked {
          background: alpha(@cd-blue, 0.18) !important;
          color: @cd-text !important;
        }

        /* Dividers */
        popover separator, menu separator { background-color: alpha(@cd-border, 0.6) !important; }

        /* Extra specificity for GtkDropDown’s popup (user/VM selectors) */
        dropdown popover,
        dropdown popover.background,
        dropdown popover > contents,
        dropdown popover listview,
        dropdown popover list,
        dropdown popover .view,
        dropdown popover row,
        dropdown popover scrolledwindow,
        dropdown popover viewport,
        dropdown popover *,
        dropdown popover.background * {
          background: @cd-surface !important;
          color: @cd-text !important;
          border-color: @cd-border !important;
        }

        /* Additional styling for combobox popovers (user/WM selectors) */
        combobox popover,
        combobox popover.background,
        combobox popover > contents,
        combobox popover listview,
        combobox popover list,
        combobox popover .view,
        combobox popover row,
        combobox popover scrolledwindow,
        combobox popover viewport,
        combobox popover *,
        combobox popover.background * {
          background: @cd-surface !important;
          color: @cd-text !important;
          border-color: @cd-border !important;
        }

        /* Additional styling for menubutton popovers */
        menubutton popover,
        menubutton popover.background,
        menubutton popover > contents,
        menubutton popover listview,
        menubutton popover list,
        menubutton popover .view,
        menubutton popover row,
        menubutton popover scrolledwindow,
        menubutton popover viewport,
        menubutton popover *,
        menubutton popover.background * {
          background: @cd-surface !important;
          color: @cd-text !important;
          border-color: @cd-border !important;
        }

        /* Ensure rows are transparent with hover/selected states */
        dropdown row,
        combobox row,
        menubutton row {
          background: transparent !important;
        }

        dropdown row:hover,
        combobox row:hover,
        menubutton row:hover {
          background: @cd-surface-2 !important;
        }

        dropdown row:selected,
        combobox row:selected,
        menubutton row:selected {
          background: alpha(@cd-blue, 0.18) !important;
        }

        /* ======================================================================= */
        /*                     OPTIONAL: Compact mode (comment in)                 */
        /* ======================================================================= */
        /* entry { min-height: 30px; padding: 8px 10px; }
        button { padding: 6px 12px; } */
      '';
    };
    systemd.tmpfiles.settings."10-regreet" =
      let
        defaultConfig = {
          user = "greeter";
          group = config.users.users.${config.services.greetd.settings.default_session.user}.group;
          mode = "0755";
        };
      in
      {
        "/var/lib/regreet".d = defaultConfig;
      };
    security.pam.services.greetd.enableGnomeKeyring = true;
    services.greetd.settings.default_session.command =
      "${dbus-run-session} ${hyprland} --config ${hyprland-conf} &> /dev/null";
  };
}
