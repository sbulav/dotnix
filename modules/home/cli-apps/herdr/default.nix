# Herdr: terminal multiplexer for AI coding agents (https://herdr.dev).
#
# Workflow: launch `herdr` on the workstation, spawn agents in panes
# (prefix+o -> opencode, prefix+shift+c -> codex), detach with prefix+q,
# then reattach later via ssh or `herdr --remote <host>` from a laptop.
# No autostart — herdr is launched manually.
{
  inputs,
  pkgs,
  config,
  lib,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.cli-apps.herdr;
in
{
  options.custom.cli-apps.herdr = {
    enable = mkBoolOpt false "Whether to enable herdr, the agent terminal multiplexer.";
    prefix =
      mkOpt types.str "ctrl+a"
        "Prefix key for herdr keybindings (distinct from wezterm's ctrl+b leader).";
  };

  config = mkIf cfg.enable {
    home.packages = [
      inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.herdr
    ];

    xdg.configFile."herdr/config.toml".text = ''
      [keys]
      prefix = "${cfg.prefix}"

      [[keys.command]]
      key = "prefix+o"
      type = "pane"
      command = "opencode"
      description = "launch opencode"

      [[keys.command]]
      key = "prefix+shift+c"
      type = "pane"
      command = "codex"
      description = "launch codex"
    '';
  };
}
