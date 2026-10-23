{
  config,
  lib,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.suites.server;
in
{
  options.suites.server = {
    enable = mkBoolOpt false "Enable the server suite";
  };

  # Headless hosts get the shared base only. Fonts, xkb, audio,
  # NetworkManager, dconf, tmux and the sys wrapper stay at their defaults
  # (off), which a host can still override.
  config = mkIf cfg.enable {
    suites.base.enable = true;
  };
}
