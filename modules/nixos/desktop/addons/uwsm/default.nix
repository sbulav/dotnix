{
  config,
  lib,
  namespace,
  ...
}:
let
  inherit (lib) mkIf;
  inherit (lib.${namespace}) mkBoolOpt;

  cfg = config.${namespace}.desktop.addons.uwsm;
in
{
  options.${namespace}.desktop.addons.uwsm = {
    # Universal Wayland Session Manager is a recommended way to start Hyprland
    # session on systemd distros.
    enable = mkBoolOpt false "Whether or not to enable uwsm";
  };

  config = mkIf cfg.enable {
    programs.uwsm = {
      enable = true;
      waylandCompositors = {
        hyprland = {
          prettyName = "Hyprland";
          comment = "Hyprland compositor managed by UWSM";
          # Launch via start-hyprland (Hyprland's official entrypoint) rather
          # than the raw Hyprland binary. Hyprland 0.55+ warns at startup
          # ("launched without start-hyprland") whenever its process is started
          # by execing the bare binary; start-hyprland sets up the session
          # correctly and silences that warning.
          binPath = "/run/current-system/sw/bin/start-hyprland";
        };
      };
    };
    services = {
      displayManager.defaultSession = "hyprland-uwsm";
    };

    # Two uwsm user templates embed the uwsm store path in ExecStart, so any
    # uwsm/util-linux bump marks them "changed" and switch-to-configuration
    # restarts their live instances mid-switch:
    #
    #  - wayland-session-bindpid@<pid>.service is a dead-man's switch
    #    (`waitpid -e <pid>` + OnSuccess=wayland-session-shutdown.target).
    #    Stopping or restarting a *running* unit fires OnSuccess= (verified
    #    empirically on systemd 260), so the restart alone pulls in the
    #    session-shutdown target.
    #  - wayland-wm@.service is the compositor itself; restarting it kills
    #    the session directly (and its OnSuccess is the same shutdown target).
    #
    # Either way the graphical session is torn down and, because nh runs
    # switch-to-configuration inside the terminal's app scope, the
    # half-finished switch is SIGKILLed along with it (services left stopped,
    # NetworkManager down). X-RestartIfChanged=false makes s-t-c leave running
    # instances alone — these units are strictly per-session, so new sessions
    # pick up the new template on their own. ConditionPathExists additionally
    # stops stale bindpid instances (dead PID ⇒ waitpid exits at once) from
    # replaying the shutdown if anything ever starts one: a failed condition
    # does not trigger OnSuccess= (also verified). wayland-wm-env@.service
    # needs no drop-in: its RefuseManualStop=yes already makes s-t-c skip it.
    systemd.user.units = {
      "wayland-session-bindpid@.service" = {
        overrideStrategy = "asDropin";
        text = ''
          [Unit]
          ConditionPathExists=/proc/%i

          [Service]
          X-RestartIfChanged=false
        '';
      };
      "wayland-wm@.service" = {
        overrideStrategy = "asDropin";
        text = ''
          [Service]
          X-RestartIfChanged=false
        '';
      };
    };
  };
}
