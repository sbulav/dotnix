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

    # force: herdr's onboarding/settings UI writes to config.toml itself;
    # without force the pre-existing file blocks home-manager activation.
    # The config is Nix-managed — settings changed in herdr's UI won't persist.
    xdg.configFile."herdr/config.toml" = {
      force = true;
      text = ''
        # Managed by Nix (custom.cli-apps.herdr) — edits here won't survive rebuilds.
        onboarding = false

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

        [ui]
        agent_panel_sort = "spaces"

        [ui.toast]
        delivery = "system"

        [experimental]
        pane_history = true
      '';
    };
  };
}
