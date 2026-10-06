{
  config,
  lib,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.desktop.addons.quake-console;
  # Always spawn a separate GUI: reusing WezTerm's existing process would
  # inherit its class and send the console to the ordinary terminal workspace.
  command = concatStringsSep " " [
    "/run/current-system/sw/bin/uwsm-app --"
    (escapeShellArg (getExe config.programs.wezterm.package))
    "start --always-new-process --class org.dotnix.quake --cwd"
    (escapeShellArg cfg.directory)
    "--"
    (escapeShellArg (getExe config.custom.cli-apps.herdr.package))
    "--session"
    (escapeShellArg cfg.sessionName)
  ];
  luaStr = s: "\"" + replaceStrings [ "\\" "\"" "\n" ] [ "\\\\" "\\\"" "\\n" ] s + "\"";
in
{
  options.custom.desktop.addons.quake-console = with types; {
    enable = mkBoolOpt false "Enable a drop-down WezTerm console with a persistent Herdr session.";
    sessionName = mkOpt str "quake" "Named Herdr session used by the console.";
    directory = mkOpt str config.home.homeDirectory "Initial working directory of the console.";
    toggleBind = mkOpt str "SUPER + grave" "Show or hide the Quake console.";
    moveBind = mkOpt str "SUPER + SHIFT + grave" "Move the focused window into the console.";
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.custom.desktop.hyprland.enable;
        message = "quake-console requires custom.desktop.hyprland.enable.";
      }
      {
        assertion = config.custom.desktop.addons.wezterm.enable && config.custom.cli-apps.herdr.enable;
        message = "quake-console requires the WezTerm and Herdr home modules.";
      }
    ];

    wayland.windowManager.hyprland.extraConfig = mkAfter ''
      -- Host opt-in console; the named Herdr session survives hiding/closing the GUI.
      local quake = dofile(${luaStr "${./quake-console.lua}"})
      quake({
        command = ${luaStr command},
        toggle_bind = ${luaStr cfg.toggleBind},
        move_bind = ${luaStr cfg.moveBind},
      })
    '';
  };
}
