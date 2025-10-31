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
  cfg = config.custom.desktop.addons.swaylock;
in
{
  options.custom.desktop.addons.swaylock = with types; {
    enable = mkBoolOpt false "Whether to enable the swaylock";
  };

  config = mkIf cfg.enable {
    programs.swaylock = {
      enable = true;
      package = pkgs.swaylock-effects;
      settings = {
        image = config.custom.desktop.addons.wallpaper;
        font-size = "24";
        indicator-idle-visible = true;
        clock = true;
        timestr = "%H:%M";
        datestr = "%A, %d %B";

        indicator = true;
        indicator-radius = "100";
        indicator-thickness = "10";

        effect-blur = "30x2";
        effect-vignette = "0.5:0.5";
      };
    };
  };
}
