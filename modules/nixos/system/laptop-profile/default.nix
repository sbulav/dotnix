{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.system.laptopProfile;

  rootController = pkgs.writeShellApplication {
    name = "laptop-profile-root";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
    ];
    text = ''
            set -euo pipefail

            profile_path="/sys/firmware/acpi/platform_profile"
            choices_path="/sys/firmware/acpi/platform_profile_choices"
            ac_online_path="${cfg.acOnlinePath}"
            state_dir="${cfg.stateDir}"
            state_file="$state_dir/profile"
            default_profile="${cfg.defaultBatteryProfile}"
            profiles=(low-power balanced performance)

            die() {
              printf 'laptop-profile-root: %s\n' "$*" >&2
              exit 1
            }

            ensure_supported() {
              [ -w "$profile_path" ] || die "$profile_path is not writable"
              [ -r "$choices_path" ] || die "$choices_path is not readable"
            }

            is_choice() {
              local wanted="$1"
              grep -qw -- "$wanted" "$choices_path"
            }

            validate_profile() {
              local wanted="$1"
              case "$wanted" in
                low-power|balanced|performance) ;;
                *) die "invalid profile: $wanted" ;;
              esac
              is_choice "$wanted" || die "profile is unsupported by this machine: $wanted"
            }

            ac_online() {
              [ -r "$ac_online_path" ] && [ "$(cat "$ac_online_path")" = 1 ]
            }

            current_profile() {
              cat "$profile_path"
            }

            saved_profile() {
              if [ -r "$state_file" ]; then
                cat "$state_file"
              else
                printf '%s\n' "$default_profile"
              fi
            }

            write_profile() {
              local profile="$1"
              validate_profile "$profile"
              printf '%s\n' "$profile" > "$profile_path"
            }

            save_profile() {
              local profile="$1"
              validate_profile "$profile"
              install -d -m 0755 "$state_dir"
              printf '%s\n' "$profile" > "$state_file"
              chmod 0644 "$state_file"
            }

            apply_profile() {
              ensure_supported
              if ac_online; then
                write_profile performance
              else
                write_profile "$(saved_profile)"
              fi
            }

            set_profile() {
              local profile="''${1:-}"
              [ -n "$profile" ] || die "missing profile"
              ensure_supported

              if ac_online; then
                write_profile performance
                return 0
              fi

              save_profile "$profile"
              write_profile "$profile"
            }

            next_profile() {
              ensure_supported

              if ac_online; then
                write_profile performance
                return 0
              fi

              local current next i
              current="$(current_profile)"
              next="low-power"
              for i in "''${!profiles[@]}"; do
                if [ "''${profiles[$i]}" = "$current" ]; then
                  next="''${profiles[$(( (i + 1) % ''${#profiles[@]} ))]}"
                  break
                fi
              done

              save_profile "$next"
              write_profile "$next"
            }

            usage() {
              cat <<USAGE
      Usage: laptop-profile-root COMMAND

      Commands:
        apply        Apply AC/battery policy
        next         Cycle battery profile, or force performance on AC
        set PROFILE  Set battery profile, or force performance on AC
      USAGE
            }

            case "''${1:-}" in
              apply) apply_profile ;;
              next) next_profile ;;
              set) shift; set_profile "$@" ;;
              -h|--help|help) usage ;;
              *) usage; exit 2 ;;
            esac
    '';
  };

  userController = pkgs.writeShellApplication {
    name = "laptop-profile";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      jq
      libnotify
      procps
      rofi
    ];
    text = ''
            set -euo pipefail

            profile_path="/sys/firmware/acpi/platform_profile"
            ac_online_path="${cfg.acOnlinePath}"
            battery_capacity_path="${cfg.batteryCapacityPath}"
            battery_status_path="${cfg.batteryStatusPath}"
            root_cmd="${rootController}/bin/laptop-profile-root"
            # Use the NixOS setuid wrapper, not the plain sudo binary —
            # `writeShellApplication` would otherwise add a non-setuid sudo to PATH.
            sudo_bin="/run/wrappers/bin/sudo"

            notify() {
              notify-send "Power profile" "$1" || true
            }

            refresh_waybar() {
              pkill -42 waybar || true
            }

            ac_online() {
              [ -r "$ac_online_path" ] && [ "$(cat "$ac_online_path")" = 1 ]
            }

            current_profile() {
              if [ -r "$profile_path" ]; then
                cat "$profile_path"
              else
                printf 'unknown\n'
              fi
            }

            icon_for_profile() {
              case "$1" in
                low-power) printf '󰌪' ;;
                balanced) printf '󰾅' ;;
                performance) printf '󰓅' ;;
                *) printf '󰌵' ;;
              esac
            }

            label_for_profile() {
              case "$1" in
                low-power) printf 'Low power' ;;
                balanced) printf 'Balanced' ;;
                performance) printf 'Performance' ;;
                *) printf 'Unknown' ;;
              esac
            }

            icon_for_capacity() {
              local capacity="''${1:-0}"
              case "$capacity" in
                ""|*[!0-9]*) printf ' ' ;;
                *)
                  if [ "$capacity" -lt 20 ]; then
                    printf ' '
                  elif [ "$capacity" -lt 40 ]; then
                    printf ' '
                  elif [ "$capacity" -lt 60 ]; then
                    printf ' '
                  elif [ "$capacity" -lt 80 ]; then
                    printf ' '
                  else
                    printf ' '
                  fi
                  ;;
              esac
            }

            class_for_capacity() {
              local capacity="''${1:-0}"
              case "$capacity" in
                ""|*[!0-9]*) return 0 ;;
              esac

              if [ "$capacity" -le 15 ]; then
                printf ' critical'
              elif [ "$capacity" -le 30 ]; then
                printf ' warning'
              fi
            }

            battery_capacity() {
              if [ -r "$battery_capacity_path" ]; then
                cat "$battery_capacity_path"
              else
                printf '?'
              fi
            }

            battery_status() {
              if [ -r "$battery_status_path" ]; then
                cat "$battery_status_path"
              else
                printf 'Unknown'
              fi
            }

            status_json() {
              local profile label profile_icon battery_icon capacity status class tooltip text capacity_class
              profile="$(current_profile)"
              label="$(label_for_profile "$profile")"
              profile_icon="$(icon_for_profile "$profile")"
              capacity="$(battery_capacity)"
              battery_icon="$(icon_for_capacity "$capacity")"
              capacity_class="$(class_for_capacity "$capacity")"
              status="$(battery_status)"

              if ac_online; then
                class="charging profile-$profile$capacity_class"
                text="$profile_icon  $capacity%"
                tooltip="Charging ($status): AC power forces $label"
              else
                class="profile-$profile$capacity_class"
                text="$profile_icon $battery_icon$capacity%"
                tooltip="Battery ($status): $label"
              fi

              jq -cn \
                --arg text "$text" \
                --arg tooltip "$tooltip" \
                --arg class "$class" \
                '{text: $text, tooltip: $tooltip, class: $class}'
            }

            run_root() {
              "$sudo_bin" -n "$root_cmd" "$@"
            }

            next_profile() {
              if ac_online; then
                run_root apply
                notify "AC power forces performance mode"
                refresh_waybar
                return 0
              fi

              run_root next
              notify "Set to $(label_for_profile "$(current_profile)")"
              refresh_waybar
            }

            set_profile() {
              local profile="''${1:-}"
              [ -n "$profile" ] || {
                printf 'laptop-profile: missing profile\n' >&2
                exit 1
              }

              if ac_online; then
                run_root apply
                notify "AC power forces performance mode"
                refresh_waybar
                return 0
              fi

              run_root set "$profile"
              notify "Set to $(label_for_profile "$profile")"
              refresh_waybar
            }

            menu() {
              if ac_online; then
                run_root apply
                notify "AC power forces performance mode"
                refresh_waybar
                exit 0
              fi

              local selected profile
              selected="$({ printf '󰌪 Low power\n'; printf '󰾅 Balanced\n'; printf '󰓅 Performance\n'; } | rofi -dmenu -i -p 'Power profile')" || exit 0
              case "$selected" in
                *Low*) profile="low-power" ;;
                *Balanced*) profile="balanced" ;;
                *Performance*) profile="performance" ;;
                *) exit 0 ;;
              esac

              set_profile "$profile"
            }

            usage() {
              cat <<USAGE
      Usage: laptop-profile COMMAND

      Commands:
        next         Cycle battery profile, or explain AC override
        set PROFILE  Set battery profile, or explain AC override
        menu         Show rofi profile picker
        status-json  Print Waybar JSON
      USAGE
            }

            case "''${1:-}" in
              next) next_profile ;;
              set) shift; set_profile "$@" ;;
              menu) menu ;;
              status-json) status_json ;;
              -h|--help|help) usage ;;
              *) usage; exit 2 ;;
            esac
    '';
  };
in
{
  options.system.laptopProfile = with types; {
    enable = mkBoolOpt false "Whether to control the firmware platform profile from Waybar.";

    user = mkOpt str "sab" "User allowed to change laptop profiles without a sudo password.";
    defaultBatteryProfile = mkOpt (enum [
      "low-power"
      "balanced"
      "performance"
    ]) "balanced" "Battery profile used when no previous battery choice is stored.";
    acOnlinePath = mkOpt str "/sys/class/power_supply/AC/online" "sysfs path used to detect AC power.";
    batteryCapacityPath =
      mkOpt str "/sys/class/power_supply/BAT0/capacity"
        "sysfs battery capacity path for Waybar.";
    batteryStatusPath =
      mkOpt str "/sys/class/power_supply/BAT0/status"
        "sysfs battery status path for Waybar.";
    stateDir =
      mkOpt str "/var/lib/laptop-profile"
        "Directory where the remembered battery profile is stored.";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      userController
      pkgs.libnotify
      pkgs.rofi
    ];

    security.sudo.extraRules = [
      {
        users = [ cfg.user ];
        commands = [
          {
            command = "${rootController}/bin/laptop-profile-root";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0755 root root -"
    ];

    systemd.services.laptop-profile-apply = {
      description = "Apply laptop platform profile policy";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-udevd.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${rootController}/bin/laptop-profile-root apply";
      };
    };

    powerManagement.resumeCommands = ''
      ${rootController}/bin/laptop-profile-root apply || true
    '';

    services.udev.extraRules = ''
      ACTION=="change", SUBSYSTEM=="power_supply", RUN+="${pkgs.systemd}/bin/systemctl start laptop-profile-apply.service"
    '';
  };
}
