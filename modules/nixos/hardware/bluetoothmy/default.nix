{
  options,
  config,
  pkgs,
  lib,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.hardware.bluetoothmy;
in
{
  options.hardware.bluetoothmy = with types; {
    enable = mkBoolOpt false "Whether or not to enable bluetooth support.";
    autoConnect =
      mkOpt (listOf str) [ ]
        "Device addresses the user session keeps reconnecting while they are powered on, for headsets that page only their last host (e.g. multipoint Sonys back to the phone).";
    musicOnly = mkBoolOpt false "Whether to offer headsets only A2DP (LDAC, AAC, SBC), with no HFP fallback.";
    fallbackSink =
      mkOpt (nullOr str) null
        "node.name of an ALSA sink that outranks every sink but the configured one, so it becomes the default whenever the configured sink is gone (a headset disconnected, or absent at boot or resume) instead of whatever WirePlumber's default-sink history ranks next.";
  };

  config = mkIf cfg.enable {
    hardware.bluetooth.enable = true;
    environment.systemPackages = with pkgs; [ blueman ];

    # Paging a powered-off device just times out, so polling is cheap. The cost:
    # a device disconnected by hand comes back within seconds.
    systemd.user.services.bluetooth-autoconnect = mkIf (cfg.autoConnect != [ ]) {
      description = "Reconnect Bluetooth devices when they power on";
      wantedBy = [ "default.target" ];
      path = [
        pkgs.bluez
        pkgs.gnugrep
        pkgs.coreutils
        config.services.pipewire.package
      ];
      script = ''
        declare -A stale
        while :; do
          for mac in ${escapeShellArgs cfg.autoConnect}; do
            if ! bluetoothctl info "$mac" | grep -q 'Connected: yes'; then
              stale[$mac]=0
              # A classic page gives up after ~5s, but BlueZ then falls back to an LE
              # connect (LE Audio headsets advertise) that runs ~45s and answers every
              # retry with br-connection-busy. Disconnect cancels the pending attempt.
              timeout 6 bluetoothctl connect "$mac" >/dev/null 2>&1 || true
              bluetoothctl info "$mac" | grep -q 'Connected: yes' \
                || bluetoothctl disconnect "$mac" >/dev/null 2>&1 || true
            # Match the node itself: the default-sink metadata also names it.
            elif pw-dump | grep -q "\"node.name\": \"bluez_output.''${mac//:/_}"; then
              stale[$mac]=0
            elif (( ++stale[$mac] >= 15 )); then
              # Still connected, but without a sink for ~30s: the audio stream died
              # (or WirePlumber restarted) and only the control channels survived.
              stale[$mac]=0
              bluetoothctl disconnect "$mac" >/dev/null 2>&1 || true
            fi
          done
          sleep 2
        done
      '';
      serviceConfig.Restart = "always";
    };

    services.pipewire.wireplumber = mkIf config.services.pipewire.wireplumber.enable {
      # PulseAudio's switch-on-connect: a Bluetooth sink that appears becomes the
      # configured default, which outranks every other node in default-nodes.
      # When the configured sink is missing, WirePlumber picks from its history,
      # but each history slot is worth only 1 point against priority.session, so
      # a high-priority sink once picked by hand (a USB mic's headphone out, say)
      # wins. fallbackSink's priority is raised below to settle that instead.
      extraScripts."custom/bluetooth-switch-on-connect.lua" = ''
        SimpleEventHook {
          name = "custom/bluetooth-switch-on-connect",
          interests = {
            EventInterest {
              Constraint { "event.type", "=", "node-added" },
              Constraint { "media.class", "=", "Audio/Sink" },
              Constraint { "device.api", "=", "bluez5" },
            },
          },
          execute = function (event)
            local name = event:get_subject ().properties ["node.name"]
            local metadata = event:get_source ():call ("get-object-manager", "metadata")
                :lookup { Constraint { "metadata.name", "=", "default" } }
            if name and metadata then
              metadata:set (0, "default.configured.audio.sink", "Spa:String:JSON",
                  Json.Object { ["name"] = name }:to_string ())
            end
          end
        }:register ()
      '';

      extraConfig."99-bluetooth-policy" = {
        "wireplumber.components" = [
          {
            name = "custom/bluetooth-switch-on-connect.lua";
            type = "script/lua";
            provides = "custom.bluetooth-switch-on-connect";
          }
        ];
        "wireplumber.profiles".main."custom.bluetooth-switch-on-connect" = "required";
        # Any capture from a headset's mic (pavucontrol's level meters included)
        # would flip it into HFP; on mz's adapter that link drops the headset.
        "wireplumber.settings"."bluetooth.autoswitch-to-headset-profile" = false;
      }
      // optionalAttrs (cfg.fallbackSink != null) {
        # A stored node scores priority.session + 20001 - its history index; ALSA
        # sinks sit around 600-1200, so 3000 wins over a history up to ~1800 deep.
        # A sink picked by hand or a connected headset is configured (+30000) and
        # still wins. An HDMI sink whose monitor is off has no available route, so
        # WirePlumber skips it and falls through to the rest.
        "monitor.alsa.rules" = [
          {
            matches = [ { "node.name" = cfg.fallbackSink; } ];
            actions.update-props."priority.session" = 3000;
          }
        ];
      }
      // optionalAttrs cfg.musicOnly {
        # Without HFP a failed A2DP stream can't fall back to an 8 kHz call profile.
        # LDAC needs a clean link: on mz without its antenna it died within a minute
        # ("Missing completion reports"), so the list keeps AAC as the fallback.
        "monitor.bluez.properties" = {
          "bluez5.roles" = [
            "a2dp_sink"
            "a2dp_source"
          ];
          "bluez5.codecs" = [
            "ldac"
            "aac"
            "sbc_xq"
            "sbc"
          ];
        };
      };
    };
  };
}
