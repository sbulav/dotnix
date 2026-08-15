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
in
{
  options.custom.desktop.addons.system-polish = with types; {
    enable = mkBoolOpt false "Enable Omarchy-inspired desktop session and system polish.";

    clamshell.enable = mkBoolOpt false "Use dock-aware lid handling for a laptop.";
  };

  config = mkIf cfg.enable {
    zramSwap = {
      enable = true;
      algorithm = "zstd";
      memoryPercent = 100;
      priority = 100;
    };

    systemd = {
      oomd = {
        enable = true;
        enableRootSlice = false;
        enableSystemSlice = false;
        enableUserSlices = false;
        settings.OOM = {
          DefaultMemoryPressureDurationSec = "20s";
          SwapUsedLimit = "90%";
        };
      };

      # UWSM places graphical applications in app.slice. Limit oomd to that
      # slice so the compositor and the rest of the session stay protected.
      user.slices.app.sliceConfig = {
        ManagedOOMMemoryPressure = "kill";
        ManagedOOMMemoryPressureLimit = "80%";
        ManagedOOMSwap = "kill";
      };

      user.services.hyprpolkitagent = {
        description = "Hyprland Polkit authentication agent";
        after = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];
        unitConfig.ConditionEnvironment = "WAYLAND_DISPLAY";
        serviceConfig = {
          ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";
          Restart = "on-failure";
          Slice = "session.slice";
        };
      };
    };

    services = {
      udisks2.enable = true;

      logind.settings.Login = mkIf cfg.clamshell.enable {
        HandleLidSwitch = "suspend";
        HandleLidSwitchExternalPower = "suspend";
        HandleLidSwitchDocked = "ignore";
      };
    };

    hardware = {
      i2c.enable = true;
      bluetooth.powerOnBoot = mkIf config.hardware.bluetooth.enable false;
    };

    environment.systemPackages = with pkgs; [
      ddcutil
      hyprpolkitagent
    ];

    users.users.${config.custom.user.name}.extraGroups = [ "i2c" ];
  };
}
