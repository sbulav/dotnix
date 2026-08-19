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
    systemd = {
      # UWSM places graphical applications in app.slice. Limit oomd (enabled
      # fleet-wide via system.memory) to that slice so the compositor and the
      # rest of the session stay protected.
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
    };

    environment.systemPackages = with pkgs; [
      ddcutil
      hyprpolkitagent
    ];

    users.users.${config.custom.user.name}.extraGroups = [ "i2c" ];
  };
}
