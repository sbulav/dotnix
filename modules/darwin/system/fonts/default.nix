{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.system.fonts;
in
{
  options.system.fonts = with types; {
    enable = mkBoolOpt false "Whether to install fonts required by the desktop configuration.";
    extraFonts = mkOpt (listOf package) [ ] "Additional font packages to install.";
  };

  config = mkIf cfg.enable {
    environment.variables.LOG_ICONS = "true";

    fonts.packages =
      with pkgs;
      [
        dejavu_fonts
        nerd-fonts.caskaydia-cove
        nerd-fonts.symbols-only
      ]
      ++ cfg.extraFonts;
  };
}
