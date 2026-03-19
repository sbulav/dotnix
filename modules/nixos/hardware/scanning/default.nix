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
  cfg = config.hardware.scanning;
in
{
  options.hardware.scanning = with types; {
    enable = mkBoolOpt false "Enable scanner support via SANE";

    drivers = mkOpt (listOf package) [
      pkgs.unstable.pantum-driver
      pkgs.sane-airscan
    ] "Extra scanner driver packages";

    openFirewall = mkBoolOpt false "Open firewall for network scanners";
  };

  config = mkIf cfg.enable {
    hardware.sane = {
      enable = true;
      inherit (cfg) openFirewall;
      extraBackends = cfg.drivers;
    };
  };
}
