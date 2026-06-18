{
  config,
  lib,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.suites.common;
in
{
  options.suites.common = with types; {
    enable = mkBoolOpt false "Enable the Darwin common suite";
  };

  config = mkIf cfg.enable {
    system = {
      fonts.enable = true;
      input.enable = true;
      interface.enable = true;
      nix.enable = true;
      security.enable = true;
    };

    custom.tools.homebrew.enable = true;

    environment.systemPath = [ "/opt/homebrew/bin" ];
  };
}
