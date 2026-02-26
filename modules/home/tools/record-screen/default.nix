{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.tools.record-screen;
in
{
  options.custom.tools.record-screen = with types; {
    enable = mkBoolOpt false "Whether to install the record-screen helper.";
    outputDir =
      mkOpt str "${config.home.homeDirectory}/Pictures/Screenrec"
        "Output directory for screen recordings.";
  };

  config = mkIf cfg.enable {
    home.packages = [ pkgs.custom.record-screen ];

    home.sessionVariables = {
      RECORD_SCREEN_DIR = cfg.outputDir;
    };
  };
}
