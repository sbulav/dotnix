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
  cfg = config.custom.desktop.addons.hypr-scale;

  scalesBash = concatStringsSep " " cfg.scales;

  # Userspace display-scale toggle for waybar. Acts on the focused monitor via
  # `hyprctl keyword monitor`, so it is runtime-only — Hyprland re-reads the
  # declarative monitor line (and its default scale) on next login.
  hyprScale = pkgs.writeShellApplication {
    name = "hypr-scale";
    runtimeInputs = with pkgs; [
      hyprland
      jq
      libnotify
      gawk
      procps
      coreutils
    ];
    text = ''
      set -uo pipefail

      scales=(${scalesBash})
      # SIGRTMIN+8 on Linux glibc = 34 + 8 = 42. waybar custom/hypr-scale listens on signal=8.
      signum=42
      hint="string:x-canonical-private-synchronous:hypr-scale"

      focused_monitor() {
        # name width height refreshRate x y scale  (tab-separated, focused monitor)
        hyprctl -j monitors \
          | jq -r '.[] | select(.focused == true)
                   | [.name, .width, .height, .refreshRate, .x, .y, .scale] | @tsv'
      }

      current_scale() {
        focused_monitor | awk -F'\t' '{printf "%s", $7}'
      }

      # hyprctl reports the live scale as e.g. 1.50; map it back to the matching
      # configured entry (1.5) for display, falling back to a trimmed value.
      canonical_scale() {
        local cur="$1" i
        for (( i = 0; i < ''${#scales[@]}; i++ )); do
          if awk -v a="$cur" -v b="''${scales[$i]}" 'BEGIN { exit !(a - b < 0.01 && b - a < 0.01) }'; then
            printf '%s' "''${scales[$i]}"
            return 0
          fi
        done
        awk -v a="$cur" 'BEGIN { printf "%g", a }'
      }

      # Pick the next scale after the current one, wrapping. If the live scale
      # is not in the configured list, fall back to the first entry.
      next_scale() {
        local cur="$1" i n idx
        n=''${#scales[@]}
        for (( i = 0; i < n; i++ )); do
          if awk -v a="$cur" -v b="''${scales[$i]}" 'BEGIN { exit !(a - b < 0.01 && b - a < 0.01) }'; then
            idx=$(( (i + 1) % n ))
            printf '%s' "''${scales[$idx]}"
            return 0
          fi
        done
        printf '%s' "''${scales[0]}"
      }

      apply_next() {
        local mon name width height refresh x y cur new rr lua
        mon="$(focused_monitor)"
        [ -n "$mon" ] || exit 0
        IFS=$'\t' read -r name width height refresh x y cur <<< "$mon"
        new="$(next_scale "$cur")"
        rr="$(awk -v r="$refresh" 'BEGIN { printf "%.0f", r }')"
        # Hyprland 0.55+ Lua configs reject `hyprctl keyword monitor`
        # ("keyword can't work with non-legacy parsers"); drive the Lua
        # hl.monitor() API via `hyprctl eval` instead — the same call the
        # Nix-generated monitor config emits at startup.
        lua="hl.monitor({ output = \"$name\", mode = \"''${width}x''${height}@''${rr}\", position = \"''${x}x''${y}\", scale = ''${new} })"
        hyprctl eval "$lua" >/dev/null
        pkill -"$signum" waybar 2>/dev/null || true
      }

      status_json() {
        local scale text tooltip
        scale="$(canonical_scale "$(current_scale)")"
        [ -n "$scale" ] || scale="?"
        text="󰍹 $scale"
        tooltip="Display scale: $scale — click to cycle, right-click for details"
        jq -cn --arg text "$text" --arg tooltip "$tooltip" '{text: $text, tooltip: $tooltip}'
      }

      info() {
        local mon name width height refresh x y scale rr lw lh body
        mon="$(focused_monitor)"
        [ -n "$mon" ] || exit 0
        IFS=$'\t' read -r name width height refresh x y scale <<< "$mon"
        rr="$(awk -v r="$refresh" 'BEGIN { printf "%.0f", r }')"
        lw="$(awk -v w="$width"  -v s="$scale" 'BEGIN { printf "%.0f", w / s }')"
        lh="$(awk -v h="$height" -v s="$scale" 'BEGIN { printf "%.0f", h / s }')"
        body="$(printf 'Resolution:  %s×%s @ %sHz\nScale:       %s×\nLogical:     %s×%s' \
          "$width" "$height" "$rr" "$(canonical_scale "$scale")" "$lw" "$lh")"
        notify-send -t 4000 -h "$hint" "󰍹 $name" "$body" || true
      }

      case "''${1:-}" in
        next) apply_next ;;
        info) info ;;
        status-json) status_json ;;
        *)
          echo "usage: $0 {next|info|status-json}" >&2
          exit 2
          ;;
      esac
    '';
  };
in
{
  options.custom.desktop.addons.hypr-scale = with types; {
    enable = mkBoolOpt false "Whether to show a display-scale toggle in Waybar.";
    scales = mkOpt (listOf str) [
      "1.0"
      "1.25"
      "1.5"
    ] "Scales the left-click toggle cycles through, in order.";
  };

  config = mkIf cfg.enable {
    home.packages = [ hyprScale ];
  };
}
