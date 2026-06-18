{ ... }:
{
  networking.hostName = "mba13";

  custom.user.enable = true;
  custom.tools.homebrew.enable = true;
  custom.apps.obsidian.enable = true;
  custom.desktop.aerospace.enable = true;
  system.fonts.enable = true;
  system.input.enable = true;
  system.interface.enable = true;
  system.nix.enable = true;
  system.security.enable = true;

  environment.systemPath = [ "/opt/homebrew/bin" ];

  # ======================== DO NOT CHANGE THIS ========================
  system.stateVersion = 7;
  # ======================== DO NOT CHANGE THIS ========================
}
