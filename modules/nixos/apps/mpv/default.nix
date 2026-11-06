{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.apps.mpv;

  associations = {
    "audio/*" = [ "mpv.desktop" ];
    "video/*" = [ "mpv.desktop" ];
  };
in
{
  options.custom.apps.mpv = {
    enable = mkBoolOpt false "Whether or not to enable mpv as the default audio/video player.";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ mpv ];

    xdg = {
      mime = {
        enable = true;
        defaultApplications = associations;
        addedAssociations = associations;
      };
    };
  };
}
