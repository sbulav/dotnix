{ ... }:
{
  networking.hostName = "mba13";

  suites.common.enable = true;
  suites.develop.enable = true;

  custom.user.enable = true;
  custom.apps.obsidian.enable = true;
  custom.desktop.aerospace.enable = true;

  # ======================== DO NOT CHANGE THIS ========================
  system.stateVersion = 7;
  # ======================== DO NOT CHANGE THIS ========================
}
