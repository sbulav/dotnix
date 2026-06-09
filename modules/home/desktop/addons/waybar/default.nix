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
  cfg = config.custom.desktop.addons.waybar;
  hyprctl = "${pkgs.hyprland}/bin/hyprctl";
  blueberry = "${pkgs.blueman}/bin/blueman-manager";
  waybar = pkgs.waybar;

  # Analog VU meter sampler — taps the mic source via pw-cat, computes peak
  # over 100 ms windows with ballistic smoothing, writes an SVG and nudges
  # waybar via SIGRTMIN+8 (= 42 on Linux glibc) to reload the image module.
  akgVuMeter = pkgs.writeShellApplication {
    name = "akg-vu-meter";
    runtimeInputs = with pkgs; [
      pipewire
      pulseaudio
      gawk
      coreutils
      procps
    ];
    text = ''
      set -uo pipefail

      SOURCE_MATCH="''${SOURCE_MATCH:-${cfg.micVuMeter.sourceMatch}}"
      SVG_PATH="''${SVG_PATH:-${cfg.micVuMeter.svgPath}}"
      TMP_PATH="''${SVG_PATH}.tmp"
      # SIGRTMIN+8 on Linux glibc = 34 + 8 = 42. waybar image#mic-vu listens on signal=8.
      SIGNUM=42

      mkdir -p "$(dirname "''${SVG_PATH}")"

      emit_placeholder() {
        cat > "''${TMP_PATH}" <<'SVG'
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 60 36" width="60" height="36">
        <rect width="60" height="36" fill="#1a1a1a" rx="3"/>
        <path d="M 10.2 16.2 A 28 28 0 0 1 49.8 16.2" stroke="#333" stroke-width="3" fill="none"/>
        <text x="30" y="22" font-family="serif" font-size="8" text-anchor="middle" fill="#666">—</text>
        <text x="30" y="32" font-family="serif" font-size="5" text-anchor="middle" fill="#666">no mic</text>
      </svg>
      SVG
        mv "''${TMP_PATH}" "''${SVG_PATH}"
        pkill -"''${SIGNUM}" waybar 2>/dev/null || true
      }

      find_source() {
        pactl list sources short 2>/dev/null \
          | awk -v m="''${SOURCE_MATCH}" '$0 ~ m {print $2; exit}'
      }

      run_meter() {
        local src="$1"
        pw-cat --record --raw --target "''${src}" \
               --rate 8000 --channels 1 --format s16 - 2>/dev/null \
          | od -An -td2 -w2 -v \
          | gawk -v svg="''${SVG_PATH}" -v tmp="''${TMP_PATH}" -v signum="''${SIGNUM}" '
            BEGIN {
              window         = 800      # 100 ms at 8 kHz
              count          = 0
              peak           = 0
              needle         = -45      # parked left
              db_floor       = -60
              is_muted       = 0
              was_muted      = -1       # force first emit
              last_emit_ang  = -999
              mute_poll_ctr  = 0
            }
            {
              v = $1; if (v < 0) v = -v
              if (v > peak) peak = v
              count++
              if (count >= window) {
                # poll mute state every 10 windows (~1 s)
                mute_poll_ctr++
                if (mute_poll_ctr >= 10) {
                  mute_poll_ctr = 0
                  cmd = "pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null"
                  mute_line = ""
                  cmd | getline mute_line
                  close(cmd)
                  is_muted = (mute_line ~ /yes/) ? 1 : 0
                }

                if (peak <= 0) {
                  db = db_floor
                } else {
                  db = 20.0 * log(peak / 32767.0) / log(10)
                }
                if (db < db_floor) db = db_floor
                if (db > 0)        db = 0

                # linear -40..0 dBFS  →  -45..+45 deg
                if      (db <= -40) target = -45
                else if (db >=   0) target =  45
                else                target = -45 + ((db + 40) / 40.0) * 90

                # ballistic smoothing: fast attack, slow decay
                if (target > needle) needle += (target - needle) * 0.35
                else                 needle += (target - needle) * 0.10

                # only re-emit when meaningful state changes — saves waybar redraws
                state_changed = (is_muted != was_muted)
                needle_moved  = (needle - last_emit_ang) ^ 2 > 0.04   # ~0.2 deg
                if (state_changed || (!is_muted && needle_moved)) {
                  if (is_muted) emit_muted()
                  else          emit_svg(needle)
                  was_muted     = is_muted
                  last_emit_ang = needle
                }

                peak  = 0
                count = 0
              }
            }
            function emit_svg(ang,   cmd) {
              printf "%s",                                                                                                  \
                "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 60 36\" width=\"60\" height=\"36\">"               \
                "<rect width=\"60\" height=\"36\" fill=\"#1a1a1a\" rx=\"3\"/>"                                              \
                "<path d=\"M 10.2 16.2 A 28 28 0 0 1 25.6 8.3\"  stroke=\"#444\"    stroke-width=\"3\" fill=\"none\"/>"     \
                "<path d=\"M 25.6 8.3  A 28 28 0 0 1 38.7 9.4\"  stroke=\"#2ecc40\" stroke-width=\"3\" fill=\"none\"/>"     \
                "<path d=\"M 38.7 9.4  A 28 28 0 0 1 44.6 12.1\" stroke=\"#ffdc00\" stroke-width=\"3\" fill=\"none\"/>"     \
                "<path d=\"M 44.6 12.1 A 28 28 0 0 1 49.8 16.2\" stroke=\"#ff4136\" stroke-width=\"3\" fill=\"none\"/>"     \
                "<text x=\"30\" y=\"31\" font-family=\"serif\" font-size=\"5\" text-anchor=\"middle\" fill=\"#aaa\">VU</text>" \
                > tmp
              printf "<line x1=\"30\" y1=\"36\" x2=\"30\" y2=\"10\" stroke=\"#fff\" stroke-width=\"1.5\" stroke-linecap=\"round\" transform=\"rotate(%.2f 30 36)\"/>", ang \
                >> tmp
              printf "<circle cx=\"30\" cy=\"36\" r=\"1.5\" fill=\"#666\"/></svg>" >> tmp
              close(tmp)
              cmd = "mv " tmp " " svg " && pkill -" signum " waybar 2>/dev/null"
              system(cmd)
            }
            function emit_muted(   cmd) {
              printf "%s",                                                                                                  \
                "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 60 36\" width=\"60\" height=\"36\">"               \
                "<rect width=\"60\" height=\"36\" fill=\"#0d0d0d\" rx=\"3\"/>"                                              \
                "<path d=\"M 10.2 16.2 A 28 28 0 0 1 49.8 16.2\" stroke=\"#3a3a3a\" stroke-width=\"3\" fill=\"none\"/>"     \
                "<line x1=\"30\" y1=\"36\" x2=\"30\" y2=\"10\" stroke=\"#5a2020\" stroke-width=\"1.5\" stroke-linecap=\"round\"/>" \
                "<circle cx=\"30\" cy=\"36\" r=\"1.5\" fill=\"#444\"/>"                                                    \
                "<line x1=\"10\" y1=\"6\" x2=\"50\" y2=\"32\" stroke=\"#ff4136\" stroke-width=\"2.5\" stroke-linecap=\"round\" opacity=\"0.85\"/>" \
                "<text x=\"30\" y=\"31\" font-family=\"sans-serif\" font-size=\"4.5\" font-weight=\"bold\" text-anchor=\"middle\" fill=\"#ff4136\">MUTE</text>" \
                "</svg>"                                                                                                    \
                > tmp
              close(tmp)
              cmd = "mv " tmp " " svg " && pkill -" signum " waybar 2>/dev/null"
              system(cmd)
            }
          '
      }

      trap 'emit_placeholder; exit 0' INT TERM

      while true; do
        src="$(find_source)"
        if [[ -z "''${src}" ]]; then
          emit_placeholder
          sleep 3
          continue
        fi
        run_meter "''${src}" || true
        emit_placeholder
        sleep 3
      done
    '';
  };

  # Click/scroll handler for the meter — toggles mute / changes gain on the
  # default audio source and emits a transient mako notification so the user
  # gets immediate feedback. The synchronous hint coalesces repeated scrolls
  # into a single replaceable popup.
  akgMicCtl = pkgs.writeShellApplication {
    name = "akg-mic-ctl";
    runtimeInputs = with pkgs; [
      wireplumber
      libnotify
      gawk
      coreutils
    ];
    text = ''
      set -uo pipefail

      action="''${1:-status}"
      src="@DEFAULT_AUDIO_SOURCE@"
      hint="string:x-canonical-private-synchronous:akg-mic"
      timeout=1500

      read_state() {
        local line vol muted_flag
        line=$(wpctl get-volume "$src" 2>/dev/null || echo "Volume: 0.00")
        vol=$(echo "$line" | awk '{printf "%d", $2 * 100}')
        if [[ "$line" == *"[MUTED]"* ]]; then muted_flag=1; else muted_flag=0; fi
        printf '%s %s\n' "$vol" "$muted_flag"
      }

      notify_state() {
        local title body icon vol muted
        read -r vol muted < <(read_state)
        if [[ "$muted" == "1" ]]; then
          icon="microphone-sensitivity-muted"
          title="🎤 Mic muted"
          body="gain ''${vol}% (no signal)"
        else
          icon="microphone-sensitivity-high"
          title="🎤 Mic active"
          body="gain ''${vol}%"
        fi
        notify-send -t "$timeout" -h "$hint" -i "$icon" "$title" "$body" || true
      }

      case "$action" in
        mute)
          wpctl set-mute "$src" toggle
          notify_state
          ;;
        vol-up)
          wpctl set-volume "$src" 5%+ -l 1.0
          notify_state
          ;;
        vol-down)
          wpctl set-volume "$src" 5%-
          notify_state
          ;;
        status)
          notify_state
          ;;
        *)
          echo "usage: $0 {mute|vol-up|vol-down|status}" >&2
          exit 2
          ;;
      esac
    '';
  };
in
{
  options.custom.desktop.addons.waybar = with types; {
    enable = mkBoolOpt false "Whether to enable Waybar in the desktop environment.";
    keyboardName =
      mkOpt str "at-translated-set-2-keyboard"
        "The keyboard device name for language switching.";

    temperature = {
      enable = mkBoolOpt true "Whether to display temperature in the stats group.";
      hwmonPath =
        mkOpt str "/sys/class/hwmon/hwmon0/temp1_input"
          "Path to the hwmon temperature sensor (e.g., /sys/class/hwmon/hwmon0/temp1_input for k10temp).";
      thermalZone = mkOpt int 0 "Thermal zone index to use if hwmonPath is not specified (fallback).";
      criticalThreshold = mkOpt int 80 "Temperature threshold in Celsius for critical warning state.";
      format = mkOpt str "{icon} {temperatureC}°C" "Format string for temperature display.";
      formatIcons = mkOpt (listOf str) [
        ""
        ""
        ""
        ""
        ""
      ] "Icons to display based on temperature levels.";
      tooltip = mkBoolOpt false "Whether to show tooltip on hover.";
    };

    memory = {
      enable = mkBoolOpt false "Whether to display memory usage in the stats group.";
    };
    disk = {
      enable = mkBoolOpt false "Whether to display disk usage in the stats group.";
    };

    micVuMeter = {
      enable = mkBoolOpt false "Show an analog VU meter for the AKG mic in waybar.";
      sourceMatch = mkOpt str "AKG_C44" "Substring matched against pactl source names to pick the mic.";
      svgPath =
        mkOpt str "${config.home.homeDirectory}/.cache/akg-vu.svg"
          "Where the meter SVG is written. Must be a stable absolute path; waybar config does not expand env vars.";
    };
  };

  config = mkIf cfg.enable {
    programs.waybar = {
      enable = true;
      package = waybar;

      systemd = {
        enable = false;
        targets = [ "hyprland-session.target" ];
      };

      style = builtins.readFile (./styles + "/${config.custom.theme.name}.css");

      settings = {
        mainBar = {
          layer = "top";
          position = "top";
          margin = "10 10 0 10";

          modules-left = [
            "hyprland/workspaces"
            "hyprland/window"
          ];

          modules-center = [
            "clock"
          ];
          modules-right = [
            "hyprland/language"
            "group/stats"
          ]
          ++ lib.optional config.custom.desktop.addons.hypr-scale.enable "custom/hypr-scale"
          ++ lib.optional cfg.micVuMeter.enable "image#mic-vu"
          ++ [
            "pulseaudio"
            "group/network"
            "tray"
            "custom/laptop-profile"
            "custom/power"
          ];

          "group/stats" = {
            orientation = "horizontal";
            modules = [
              "cpu"
            ]
            ++ lib.optionals cfg.memory.enable [ "memory" ]
            ++ lib.optionals cfg.disk.enable [ "disk" ]
            ++ lib.optionals cfg.temperature.enable [ "temperature" ];
          };
          "group/network" = {
            orientation = "horizontal";
            modules = [
              "bluetooth"
              "network"
            ];
          };
          bluetooth = {
            "format" = "󰂯";
            "format-disabled" = "󰂲";
            "format-connected" = "󰂱";
            "tooltip-format" = "{controller_alias}\t{controller_address}";
            "tooltip-format-connected" = "{controller_alias}\t{controller_address}\n\n{device_enumerate}";
            "tooltip-format-enumerate-connected" = "{device_alias}\t\t{device_address}";
            "on-click" = "blueman-manager";
          };

          "hyprland/workspaces" = {
            format = "{icon} {windows}";
            all-outputs = false;
            on-scroll-up = "${getExe' config.wayland.windowManager.hyprland.package "hyprctl"} dispatch workspace e+1";
            on-scroll-down = "${getExe' config.wayland.windowManager.hyprland.package "hyprctl"} dispatch workspace e-1";
            active-only = false;
            format-icons = {
              "1" = "󰎤";
              "2" = "󰎧";
              "3" = "󰎪";
              "4" = "󰎭";
              "5" = "󰎱";
              "6" = "󰎳";
              "7" = "󰎶";
              "8" = "󰎹";
              "9" = "󰎼";
              "10" = "󰽽";
              "urgent" = "󱨇";
              "default" = "";
              "empty" = "󱓼";
            };
            window-rewrite-default = "";
            window-rewrite = {
              "class<1Password>" = "󰢁";
              "class<Caprine>" = "󰈎";
              "class<Github Desktop>" = "󰊤";
              "class<Godot>" = "";
              "class<Mysql-workbench-bin>" = "";
              "class<Slack>" = "󰒱";
              "class<zoom>" = "󱋒";
              "class<Zoom Meeting>" = "󱋒";
              "class<ktalk>" = "☎️";
              "class<obsidian>" = "📓";
              "class<code>" = "󰨞";
              "code-url-handler" = "󰨞";
              "class<discord>" = "󰙯";
              "class<firefox>" = "";
              "class<firefox> title<.*github.*>" = "";
              "class<firefox> title<.*twitch|youtube|plex|tntdrama|bally sports.*>" = "";
              "class<kitty>" = "";
              "class<org.wezfurlong.wezterm>" = "";
              "class<mediainfo-gui>" = "󱂷";
              "class<org.kde.digikam>" = "󰄄";
              "class<org.telegram.desktop>" = "";
              "class<.pitivi-wrapped>" = "󱄢";
              "class<steam>" = "";
              "class<thunderbird>" = "";
              "class<virt-manager>" = "󰢹";
              "class<vlc>" = "󰕼";
              "class<thunar>" = "󰉋";
              "class<org.gnome.Nautilus>" = "󰉋";
              "class<Spotify>" = "";
              "title<Spotify Free>" = "";
              "class<libreoffice-draw>" = "󰽉";
              "class<libreoffice-writer>" = "";
              "class<libreoffice-calc>" = "󱎏";
              "class<libreoffice-impress>" = "󱎐";
            };
          };

          "hyprland/window" = {
            max-length = 25;
            separate-outputs = true;
          };
          "cpu" = {
            format = " {usage}%";
            tooltip = false;
            on-click = "wezterm -e btm";
          };
          "memory" = lib.mkIf cfg.memory.enable {
            format = " {}%";
          };
          "disk" = lib.mkIf cfg.disk.enable {
            interval = 30;
            format = " {percentage_used}%";
            path = "/";
          };
          "clock" = {
            format = "  {:%b %d %H:%M}";
            tooltip-format = "<b><big>{:%Y %B}</big></b>\n\n<tt>{calendar}</tt>";
            format-alt = "{:%Y-%m-%d}";
          };
          "temperature" = lib.mkIf cfg.temperature.enable {
            thermal-zone = cfg.temperature.thermalZone;
            hwmon-path = cfg.temperature.hwmonPath;
            critical-threshold = cfg.temperature.criticalThreshold;
            format = cfg.temperature.format;
            format-icons = cfg.temperature.formatIcons;
            tooltip = cfg.temperature.tooltip;
          };
          "custom/kernel" = {
            interval = "once";
            format = " {}";
            exec = "uname -r";
          };
          network = {
            # Left-click toggles format-alt (bandwidth); right-click opens the rofi
            # network picker — this replaces the removed nm-applet tray menu.
            on-click-right = "${pkgs.networkmanager_dmenu}/bin/networkmanager_dmenu";
            format-wifi = "󰖩 {signalStrength}%";
            format-ethernet = "{ifname}: {ipaddr}/{cidr} 󰈀";
            format-linked = "{ifname} (No IP) 󰈀";
            format-disconnected = "󰖪";
            format-alt = "  󰜮 {bandwidthDownBytes} 󰜷 {bandwidthUpBytes}";
          };
          pulseaudio = {
            scroll-step = 5;
            tooltip = true;
            tooltip-format = "{volume}% {format_source}";
            on-click-right = "${pkgs.pavucontrol}/bin/pavucontrol";
            on-click = "${pkgs.pamixer}/bin/pamixer -t";
            format = "{icon} {volume}%";
            format-bluetooth = "󰂯 {icon} {volume}%";
            format-muted = "󰝟 0%";
            format-icons = {
              default = [
                ""
                ""
                " "
              ];
            };
          };
          "image#mic-vu" = lib.mkIf cfg.micVuMeter.enable {
            path = cfg.micVuMeter.svgPath;
            size = 30;
            signal = 8; # SIGRTMIN+8 — the sampler nudges waybar at ~10 Hz
            interval = 5; # fallback re-poll if a signal was missed at startup
            tooltip = true;
            on-click = "${akgMicCtl}/bin/akg-mic-ctl mute";
            on-click-right = "${pkgs.pavucontrol}/bin/pavucontrol -t 3";
            on-scroll-up = "${akgMicCtl}/bin/akg-mic-ctl vol-up";
            on-scroll-down = "${akgMicCtl}/bin/akg-mic-ctl vol-down";
          };

          "hyprland/language" = {
            # "format-dh" = " dh";
            "format-en" = "  dh";
            "format-ru" = "  ru";
            "keyboard-name" = cfg.keyboardName;
            on-click = "${hyprctl} switchxkblayout ${cfg.keyboardName} next";
          };
          "custom/laptop-profile" = {
            exec = "laptop-profile status-json";
            format = "{}";
            interval = 5;
            on-click = "laptop-profile next";
            on-click-right = "laptop-profile menu";
            return-type = "json";
            signal = 8;
            tooltip = true;
          };
          "custom/hypr-scale" = lib.mkIf config.custom.desktop.addons.hypr-scale.enable {
            exec = "hypr-scale status-json";
            return-type = "json";
            format = "{}";
            interval = 5; # slow fallback; on-click refreshes via SIGRTMIN+8
            signal = 8;
            on-click = "hypr-scale next";
            on-click-right = "hypr-scale info";
            tooltip = true;
          };
          "tray" = {
            spacing = 10;
          };
          "custom/power" = {
            format = "";
            on-click = "wlogout -p layer-shell";
          };
        };
      };
    };

    # Cross-cutting bits that exist because waybar now owns the bluetooth and
    # network indicators — co-located here to keep the "waybar is the single
    # status surface" decision in one place.
    xdg.configFile = {
      # blueman-applet autostarts via /etc/xdg/autostart/blueman.desktop (blueman
      # is in systemPackages + xdg.autostart.enable). Waybar's bluetooth module is
      # now the sole BT indicator, so shadow the system entry to stop the duplicate
      # tray applet. blueman-manager (the GUI, opened on bar click) stays available.
      "autostart/blueman.desktop".text = ''
        [Desktop Entry]
        Hidden=true
      '';
      # Backs the network module's right-click picker; drive it through rofi
      # (already this session's launcher) instead of the default dmenu.
      "networkmanager-dmenu/config.ini".text = ''
        [dmenu]
        dmenu_command = rofi
        highlight = True
        compact = True
        wifi_chars = ▂▄▆█
        prompt = Networks

        [editor]
        gui_if_available = True
        gui = nm-connection-editor
      '';
    };

    systemd.user.services.akg-vu-meter = mkIf cfg.micVuMeter.enable {
      Unit = {
        Description = "AKG Lyra VU meter renderer for waybar";
        After = [
          "pipewire.service"
          "wireplumber.service"
        ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${akgVuMeter}/bin/akg-vu-meter";
        Restart = "on-failure";
        RestartSec = 3;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
