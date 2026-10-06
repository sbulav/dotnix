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
  raw = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.herdr;
  real = getExe raw;
  herdrDir = "${config.xdg.configHome}/herdr";

  # herdr keeps one long-lived server per session, and the client/server
  # protocol changes between releases: after a flake bump the old server
  # keeps running while freshly built clients can no longer attach to it.
  # The wrapper asks the session's socket which binary is listening and
  # attaches with that one; `herdr server stop` then picks up the new build.
  # Every lookup failure falls through to the current build. Linux-only:
  # it reads the listener from ss and /proc.
  wrapper = pkgs.writeShellApplication {
    name = "herdr";
    runtimeInputs = [
      pkgs.iproute2
      pkgs.coreutils
    ];
    text = ''
      real=${escapeShellArg real}

      # Session named on the command line: --session NAME, --session=NAME,
      # or `session attach NAME`. --remote attaches over SSH, not here.
      session=""
      have_session=0
      prev=""
      prev2=""
      for arg in "$@"; do
        case "$arg" in
          --remote | --remote=*) exec "$real" "$@" ;;
          --session=*)
            session="''${arg#--session=}"
            have_session=1
            ;;
        esac
        if [ "$prev" = "--session" ]; then
          session="$arg"
          have_session=1
        elif [ "$prev2" = "session" ] && [ "$prev" = "attach" ]; then
          session="$arg"
          have_session=1
        fi
        prev2="$prev"
        prev="$arg"
      done

      base="''${XDG_CONFIG_HOME:-''${HOME:-}/.config}/herdr"
      if [ "$have_session" = 0 ]; then
        # herdr exports HERDR_SOCKET_PATH into its panes.
        sock="''${HERDR_SOCKET_PATH:-$base/herdr.sock}"
        stop="herdr server stop"
      elif [ "$session" = default ]; then
        sock="$base/herdr.sock"
        stop="herdr server stop"
      else
        sock="$base/sessions/$session/herdr.sock"
        stop="herdr --session $session server stop"
      fi

      exe=""
      listing="$(ss -xlpnH src "$sock" 2>/dev/null || true)"
      if [[ "$listing" =~ pid=([0-9]+) ]]; then
        exe="$(readlink "/proc/''${BASH_REMATCH[1]}/exe" 2>/dev/null || true)"
      fi
      if [ -n "$exe" ] && [ -x "$exe" ] && [ "$exe" != "$real" ]; then
        echo "herdr: attaching with running server's binary ($exe); run '$stop' to upgrade" >&2
        exec -a herdr "$exe" "$@"
      fi
      exec "$real" "$@"
    '';
  };
in
{
  options.custom.cli-apps.herdr = {
    enable = mkBoolOpt false "Whether to enable herdr, the agent terminal multiplexer.";
    prefix =
      mkOpt types.str "ctrl+a"
        "Prefix key for herdr keybindings (distinct from wezterm's ctrl+b leader).";
    package = mkOption {
      type = types.package;
      readOnly = true;
      default = if pkgs.stdenv.isLinux then wrapper else raw;
      description = "The herdr command every client should run (the stale-server wrapper on Linux).";
    };
  };

  config = mkIf cfg.enable {
    # The raw package ships only bin/herdr, so the wrapper replaces it whole.
    home.packages = [ cfg.package ];

    # Report, never stop: a server still on the previous build keeps working
    # through the wrapper and holds live panes, so upgrading it is the user's call.
    home.activation.herdrStaleServer = mkIf pkgs.stdenv.isLinux (
      config.lib.dag.entryAfter [ "linkGeneration" ] ''
        herdrStaleServer() {
          local sock name listing exe stop
          for sock in ${escapeShellArg herdrDir}/herdr.sock ${escapeShellArg herdrDir}/sessions/*/herdr.sock; do
            [ -S "$sock" ] || continue
            listing="$(${pkgs.iproute2}/bin/ss -xlpnH src "$sock" 2>/dev/null || true)"
            [[ "$listing" =~ pid=([0-9]+) ]] || continue
            exe="$(${pkgs.coreutils}/bin/readlink "/proc/''${BASH_REMATCH[1]}/exe" 2>/dev/null || true)"
            if [ -z "$exe" ] || [ "$exe" = ${escapeShellArg real} ]; then
              continue
            fi
            if [ "$sock" = ${escapeShellArg herdrDir}/herdr.sock ]; then
              name=default
              stop="herdr server stop"
            else
              name="''${sock%/herdr.sock}"
              name="''${name##*/}"
              stop="herdr --session $name server stop"
            fi
            echo "herdr: session '$name' still runs $exe; new clients use ${real}." \
              "Clients attach with the old binary until you run '$stop'."
          done
        }
        herdrStaleServer || true
      ''
    );

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
        next_agent = "prefix+shift+n"
        previous_agent = "prefix+shift+p"

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
        # Kitty graphics is herdr's only image protocol; without it, image
        # previews inside a pane render nothing. Upstream keeps it off by
        # default. custom.cli-apps.yazi steers yazi onto this adapter by
        # clearing the WezTerm env leak in herdr panes — see the comment there.
        kitty_graphics = true
      '';
    };
  };
}
