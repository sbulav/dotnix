{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.${namespace}.containers.ups;

  # Local-only NUT credential shared by the upsd user and the upsmon monitor.
  # upsd listens on 127.0.0.1 only, so this password guards nothing remotely;
  # it is auto-generated on first boot (root-only, kept out of the nix store
  # and out of sops). upsd.users and upsmon.monitor read the SAME file so the
  # passwords always match.
  passwordFile = "/var/lib/nut/monitor.password";

  ups = "ups@localhost";

  # Dispatched by upssched (runs as root, child of upsmon). Sends an email via
  # the already-configured msmtp Gmail relay and, for terminal power events,
  # issues a clean NUT forced shutdown (`upsmon -c fsd`) so POWERDOWNFLAG /
  # killpower handling still applies.
  upsschedCmd = pkgs.writeShellScript "ups-upssched-cmd" ''
    set -u
    export PATH=${
      lib.makeBinPath [
        config.power.ups.package
        pkgs.msmtp
        pkgs.coreutils
      ]
    }:$PATH

    status="$(upsc ${ups} ups.status 2>/dev/null || echo '?')"
    charge="$(upsc ${ups} battery.charge 2>/dev/null || echo '?')"
    runtime="$(upsc ${ups} battery.runtime 2>/dev/null || echo '?')"

    send() {
      printf 'From: ZANOZA UPS <zppfan@gmail.com>\nTo: %s\nSubject: %s\n\n%s\n' \
        "${cfg.notifyEmail}" "$1" "$2" \
        | msmtp -a gmail "${cfg.notifyEmail}" || true
    }

    case "$1" in
      onbatt)
        send "[zanoza] UPS ON BATTERY" "Utility power lost. status=$status charge=$charge% runtime=$runtime s. Will shut down when runtime drops below ${toString cfg.runtimeLow}s (~${toString (cfg.runtimeLow / 60)} min) unless power returns." ;;
      online)
        send "[zanoza] UPS back ONLINE" "Utility power restored. status=$status charge=$charge%." ;;
      lowbatt)
        send "[zanoza] UPS LOW BATTERY - shutting down" "runtime=$runtime s left (threshold ${toString cfg.runtimeLow}s). status=$status charge=$charge%. Forcing graceful shutdown now."
        upsmon -c fsd ;;
      commbad)
        send "[zanoza] UPS COMM LOST" "upsmon lost communication with the UPS. status=$status" ;;
      commok)
        send "[zanoza] UPS comm restored" "upsmon re-established communication with the UPS. status=$status" ;;
    esac
  '';

  upsschedConf = pkgs.writeText "upssched.conf" ''
    CMDSCRIPT ${upsschedCmd}
    PIPEFN /run/nut/upssched.pipe
    LOCKFN /run/nut/upssched.lock

    # Runtime-based shutdown: we do NOT shut down on a fixed on-battery timer.
    # Instead `ignorelb` + `override.battery.runtime.low` make the driver raise
    # the LB flag once the UPS reports less than runtimeLow seconds remaining,
    # which fires LOWBATT below and issues the graceful shutdown.
    AT LOWBATT * EXECUTE lowbatt

    # Email notifications for every relevant power event.
    AT ONBATT  * EXECUTE onbatt
    AT ONLINE  * EXECUTE online
    AT COMMBAD * EXECUTE commbad
    AT COMMOK  * EXECUTE commok
  '';
in
{
  options.${namespace}.containers.ups = with types; {
    enable = mkBoolOpt false "Enable UPS monitoring";
    driver = mkOpt str "huawei-ups2000" "Driver to use to connect to UPS";
    port = mkOpt str "/dev/ttyUSB0" "Port to connect";
    runtimeLow =
      mkOpt int 300
        "Battery runtime (seconds) remaining at which a graceful shutdown is triggered";
    notifyEmail = mkOpt str "zppfan@gmail.com" "Address for UPS power-event email notifications";
  };

  config = mkIf cfg.enable {
    # Auto-generate the local upsd/upsmon password once, root-only.
    systemd.services.nut-monitor-password = {
      description = "Generate local NUT upsmon password";
      wantedBy = [ "multi-user.target" ];
      before = [
        "upsd.service"
        "upsmon.service"
      ];
      requiredBy = [
        "upsd.service"
        "upsmon.service"
      ];
      unitConfig.ConditionPathExists = "!${passwordFile}";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        umask 077
        mkdir -p /var/lib/nut
        ${pkgs.coreutils}/bin/head -c 18 /dev/urandom \
          | ${pkgs.coreutils}/bin/base64 > ${passwordFile}
        chmod 400 ${passwordFile}
      '';
    };

    # Runtime dir for upssched PIPEFN/LOCKFN.
    systemd.tmpfiles.rules = [ "d /run/nut 0700 root root -" ];

    # Enable and configure UPS monitoring
    power.ups = {
      enable = true;
      # This mode address a local only configuration, with 1 UPS protecting the
      # local system. This implies to start the 3 NUT layers (driver, upsd and
      # upsmon) and the matching configuration files. This mode can also
      # address UPS redundancy.
      mode = "standalone";

      ups.ups = {
        # find your driver here:
        # https://networkupstools.org/docs/man/usbhid-ups.html
        driver = cfg.driver;
        description = "Huawei UPS2000-G1KRTS";
        port = cfg.port;
        directives = [
          "offdelay = 60"
          "ondelay = 120"
          # Runtime-based low-battery: ignore the UPS's own LB flag and instead
          # raise LB when reported runtime drops below runtimeLow seconds. This
          # is what drives the shutdown (LOWBATT -> upsmon -c fsd), so we run on
          # battery for as long as the UPS estimates it can, and only shut down
          # with ~runtimeLow seconds of headroom left.
          "ignorelb"
          "override.battery.runtime.low = ${toString cfg.runtimeLow}"
        ];
        # this option is not valid for usbhid-ups
        maxStartDelay = null;
      };

      maxStartDelay = 10;

      # Run upsmon as root so its NOTIFYCMD (upssched -> upsschedCmd) can read
      # the msmtp secret, send mail, and issue `upsmon -c fsd`. upsd/upsdrv
      # already run as root.
      upsmon = {
        user = "root";
        monitor.ups = {
          system = ups;
          user = "upsmon";
          passwordFile = passwordFile;
          type = "primary";
        };
        settings = {
          MINSUPPLIES = 1; # FIX: was 0, which disabled shutdown entirely
          NOTIFYCMD = "${config.power.ups.package}/bin/upssched";
          NOTIFYFLAG = [
            [
              "ONBATT"
              "SYSLOG+EXEC"
            ]
            [
              "ONLINE"
              "SYSLOG+EXEC"
            ]
            [
              "LOWBATT"
              "SYSLOG+EXEC"
            ]
            [
              "FSD"
              "SYSLOG+EXEC"
            ]
            [
              "SHUTDOWN"
              "SYSLOG+EXEC"
            ]
            [
              "COMMBAD"
              "SYSLOG+EXEC"
            ]
            [
              "COMMOK"
              "SYSLOG+EXEC"
            ]
          ];
        };
      };

      users.upsmon = {
        passwordFile = passwordFile;
        upsmon = "primary";
      };

      schedulerRules = "${upsschedConf}";
    };
  };
}
