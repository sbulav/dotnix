{
  lib,
  writeShellApplication,
  coreutils,
  gawk,
  hyprland,
  hyprpicker,
  jq,
  slurp,
  ...
}:
writeShellApplication {
  name = "capture-region";

  meta = {
    description = "Select an arbitrary Hyprland region or snap a click to a window or monitor";
    mainProgram = "capture-region";
    platforms = lib.platforms.linux;
  };

  runtimeInputs = [
    coreutils
    gawk
    hyprland
    hyprpicker
    jq
    slurp
  ];

  text = ''
    set -euo pipefail

    freeze=false
    if [[ ''${1:-} == --freeze ]]; then
      freeze=true
      shift
    fi

    if [[ ''${1:-} == -- ]]; then
      shift
    fi

    picker_pid=""
    cleanup() {
      if [[ -n $picker_pid ]]; then
        kill "$picker_pid" 2>/dev/null || true
      fi
    }
    trap cleanup EXIT

    # jq source is intentionally literal; jq, not the shell, expands $x etc.
    # shellcheck disable=SC2016
    monitor_geometry='
      def geometry:
        .x as $x | .y as $y |
        (.width / .scale | floor) as $w |
        (.height / .scale | floor) as $h |
        .transform as $transform |
        if $transform == 1 or $transform == 3 then
          "\($x),\($y) \($h)x\($w)"
        else
          "\($x),\($y) \($w)x\($h)"
        end;
    '

    active_workspace=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .activeWorkspace.id')
    rectangles=$(
      {
        hyprctl monitors -j | jq -r --arg ws "$active_workspace" \
          "$monitor_geometry .[] | select(.activeWorkspace.id == (\$ws | tonumber)) | geometry"
        hyprctl clients -j | jq -r --arg ws "$active_workspace" \
          '.[] | select(.workspace.id == ($ws | tonumber)) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"'
      } | awk '!seen[$0]++'
    )

    if [[ $freeze == true ]]; then
      hyprpicker -r -z >/dev/null 2>&1 &
      picker_pid=$!
      sleep 0.1
    fi

    selection=$(printf '%s\n' "$rectangles" | slurp 2>/dev/null) || exit 1
    [[ $selection =~ ^(-?[0-9]+),(-?[0-9]+)[[:space:]]([0-9]+)x([0-9]+)$ ]] || exit 1

    sx=''${BASH_REMATCH[1]}
    sy=''${BASH_REMATCH[2]}
    sw=''${BASH_REMATCH[3]}
    sh=''${BASH_REMATCH[4]}

    # A click is represented by a tiny slurp rectangle. Snap it to the first
    # advertised window or monitor containing the point; a real drag remains
    # an arbitrary region.
    if ((sw * sh < 20)); then
      while IFS= read -r rectangle; do
        [[ $rectangle =~ ^(-?[0-9]+),(-?[0-9]+)[[:space:]]([0-9]+)x([0-9]+)$ ]] || continue
        rx=''${BASH_REMATCH[1]}
        ry=''${BASH_REMATCH[2]}
        rw=''${BASH_REMATCH[3]}
        rh=''${BASH_REMATCH[4]}
        if ((sx >= rx && sx < rx + rw && sy >= ry && sy < ry + rh)); then
          sx=$rx
          sy=$ry
          sw=$rw
          sh=$rh
          break
        fi
      done <<< "$rectangles"
    fi

    export CAPTURE_GEOMETRY="$sx,$sy ''${sw}x$sh"

    if (($# > 0)); then
      "$@"
    else
      printf '%s\n' "$CAPTURE_GEOMETRY"
    fi
  '';
}
