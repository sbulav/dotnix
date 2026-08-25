{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.desktop.addons.system-polish;

  displayBrightness = pkgs.writeShellApplication {
    name = "display-brightness";
    runtimeInputs = with pkgs; [
      brightnessctl
      coreutils
      ddcutil
      hyprland
      jq
    ];
    text = ''
      set -uo pipefail

      direction="''${1:-}"
      case "$direction" in
        up) delta=(+ 5) ;;
        down) delta=(- 5) ;;
        *)
          echo "usage: $0 {up|down}" >&2
          exit 2
          ;;
      esac

      output="$(hyprctl -j monitors 2>/dev/null | jq -r '.[] | select(.focused == true) | .name' | head -n 1)"
      [ -n "$output" ] || exit 0

      case "$output" in
        eDP-*|LVDS-*|DSI-*)
          if [ "$direction" = up ]; then
            brightnessctl set 5%+ >/dev/null 2>&1 || true
          else
            brightnessctl set 5%- >/dev/null 2>&1 || true
          fi
          ;;
        *)
          drm_path=""
          for candidate in /sys/class/drm/card*-"$output"; do
            if [ -e "$candidate" ]; then
              drm_path="$candidate"
              break
            fi
          done
          [ -n "$drm_path" ] || exit 0

          for bus_path in "$drm_path"/ddc/i2c-dev/i2c-*; do
            [ -e "$bus_path" ] || continue
            bus="''${bus_path##*-}"
            ddcutil --bus "$bus" setvcp 10 "''${delta[@]}" >/dev/null 2>&1 || true
            exit 0
          done
          ;;
      esac
    '';
  };

  audioOutputCycle = pkgs.writeShellApplication {
    name = "audio-output-cycle";
    runtimeInputs = with pkgs; [
      coreutils
      jq
      libnotify
      pulseaudio
    ];
    text = ''
      set -euo pipefail

      sinks=$(pactl -f json list sinks \
        | jq '[.[] | select((.ports | length == 0) or ([.ports[]? | .availability != "not available"] | any))]')
      count=$(jq 'length' <<< "$sinks")
      if ((count == 0)); then
        notify-send -a audio-output-cycle -u normal "Audio output" "No available output devices"
        exit 1
      fi

      current=$(pactl get-default-sink)
      current_index=$(jq -r --arg current "$current" 'map(.name) | index($current)' <<< "$sinks")
      if [[ $current_index == null ]]; then
        next_index=0
      else
        next_index=$(((current_index + 1) % count))
      fi

      next=$(jq -c ".[$next_index]" <<< "$sinks")
      name=$(jq -r '.name' <<< "$next")
      description=$(jq -r '.description // .name' <<< "$next")
      muted=$(jq -r '.mute' <<< "$next")
      volume=$(jq -r '[.volume[].value_percent | sub("%"; "") | tonumber] | add / length | round' <<< "$next")

      pactl set-default-sink "$name"
      while IFS= read -r input; do
        [[ -n $input ]] && pactl move-sink-input "$input" "$name" || true
      done < <(pactl -f json list sink-inputs | jq -r '.[].index')

      if [[ $muted == true ]]; then
        icon=audio-volume-muted
        detail="muted"
      elif ((volume <= 33)); then
        icon=audio-volume-low
        detail="''${volume}%"
      elif ((volume <= 66)); then
        icon=audio-volume-medium
        detail="''${volume}%"
      else
        icon=audio-volume-high
        detail="''${volume}%"
      fi

      idfile="''${XDG_RUNTIME_DIR:-/tmp}/audio-output-cycle.notify-id"
      previous=$(cat "$idfile" 2>/dev/null || true)
      args=(-a audio-output-cycle -p -t 1800 -i "$icon")
      [[ $previous =~ ^[0-9]+$ ]] && args+=(-r "$previous")
      notify-send "''${args[@]}" "Audio output" "$description · $detail" > "$idfile" || true
    '';
  };

  clamshell = pkgs.writeShellApplication {
    name = "hyprland-clamshell";
    runtimeInputs = with pkgs; [
      coreutils
      gawk
      hyprland
      jq
      systemd
    ];
    text = ''
      set -uo pipefail

      internal=${escapeShellArg cfg.clamshell.internalOutput}
      mode=${escapeShellArg cfg.clamshell.mode}
      position=${escapeShellArg cfg.clamshell.position}
      scale=${escapeShellArg cfg.clamshell.scale}

      lid_path=""
      for candidate in /proc/acpi/button/lid/*/state; do
        if [ -r "$candidate" ]; then
          lid_path="$candidate"
          break
        fi
      done
      [ -n "$lid_path" ] || exit 0

      lid_state() {
        awk '{ print tolower($2) }' "$lid_path"
      }

      external_active() {
        hyprctl -j monitors 2>/dev/null | jq -e --arg internal "$internal" 'any(.[]; .name != $internal)' >/dev/null
      }

      set_internal_disabled() {
        hyprctl eval "hl.monitor({ output = \"$internal\", disabled = true })" >/dev/null 2>&1 || true
      }

      restore_internal() {
        hyprctl eval "hl.monitor({ output = \"$internal\", mode = \"$mode\", position = \"$position\", scale = $scale })" >/dev/null 2>&1 || true
      }

      previous_lid=""
      previous_external=""

      while sleep 1; do
        lid="$(lid_state)"
        external=false
        if external_active; then
          external=true
        fi

        if [ "$lid" = "$previous_lid" ] && [ "$external" = "$previous_external" ]; then
          continue
        fi
        previous_lid="$lid"
        previous_external="$external"

        if [ "$lid" = closed ]; then
          if [ "$external" = true ]; then
            set_internal_disabled
          else
            systemctl suspend
          fi
        else
          restore_internal
        fi
      done
    '';
  };
in
{
  options.custom.desktop.addons.system-polish = with types; {
    enable = mkBoolOpt false "Enable Omarchy-inspired desktop session polish.";

    clamshell = {
      enable = mkBoolOpt false "Manage the internal display according to lid and dock state.";
      internalOutput = mkOpt str "eDP-1" "Name of the laptop's internal display.";
      mode = mkOpt str "preferred" "Mode restored when the lid opens.";
      position = mkOpt str "auto" "Position restored when the lid opens.";
      scale = mkOpt str "1" "Scale restored when the lid opens.";
    };

    audioOutputCycle.enable = mkBoolOpt false "Install a helper that cycles available PipeWire output devices.";
  };

  config = mkIf cfg.enable {
    home.packages = [ displayBrightness ] ++ optional cfg.audioOutputCycle.enable audioOutputCycle;

    services.udiskie = {
      enable = true;
      automount = true;
      notify = false;
      tray = "never";
    };

    systemd.user.services = {
      # These are session infrastructure, not disposable application scopes.
      udiskie.Service.Slice = "session.slice";
      hypridle.Service.Slice = mkIf config.custom.desktop.addons.hypridle.enable "session.slice";
      hyprpaper.Service.Slice = mkIf config.custom.desktop.addons.hyprpaper.enable "session.slice";

      hyprland-clamshell = mkIf cfg.clamshell.enable {
        Unit = {
          Description = "Dock-aware Hyprland clamshell manager";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
          ConditionEnvironment = "WAYLAND_DISPLAY";
        };
        Service = {
          ExecStart = "${clamshell}/bin/hyprland-clamshell";
          Restart = "on-failure";
          RestartSec = 2;
          Slice = "session.slice";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
