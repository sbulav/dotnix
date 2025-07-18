{
  options,
  config,
  pkgs,
  lib,
  ...
}:
with lib;
with lib.custom; let
  cfg = config.custom.system.fonts;
in {
  options.custom.system.fonts = with types; {
    enable = mkBoolOpt false "Whether or not to manage fonts.";
    fonts = mkOpt (listOf package) [] "Custom font packages to install.";
  };

  config = mkIf cfg.enable {
    environment.variables = {
      # Enable icons in tooling since we have nerdfonts.
      LOG_ICONS = "true";
    };

    fonts = {
      packages = with pkgs;
        [
          noto-fonts
          dejavu_fonts
          nerd-fonts.jetbrains-mono
          nerd-fonts.caskaydia-cove
          nerd-fonts.fira-code
          noto-fonts-cjk-sans
          noto-fonts-cjk-serif
          noto-fonts-emoji
        ]
        ++ cfg.fonts;
    };
  };
}
