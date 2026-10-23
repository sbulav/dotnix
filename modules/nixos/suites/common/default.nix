{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.suites.common;
in
{
  options.suites.common = {
    enable = mkBoolOpt false "Enable the common suite";
  };

  # Workstations: the shared base plus the desktop-facing hardware and tools.
  config = mkIf cfg.enable {
    suites.base.enable = true;

    system = {
      fonts.enable = true;
      xkb.enable = true;
    };

    hardware.audio.enable = true;
    hardware.networking.enable = true;

    programs.dconf.enable = true;

    # add sys custom build package
    environment.systemPackages = [ pkgs.custom.sys ];

    custom.cli-apps.tmux.enable = mkDefault true;
  };
}
