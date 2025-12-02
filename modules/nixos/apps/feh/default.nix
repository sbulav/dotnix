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
  cfg = config.custom.apps.feh;

  # XDG MIME types
  associations = {
    "image/*" = [ "feh.desktop" ];
  };
in
{
  options.custom.apps.feh = with types; {
    enable = mkBoolOpt false "Whether or not to enable feh.";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ feh ];

    xdg = {
      mime = {
        enable = true;
        defaultApplications = associations;
        addedAssociations = associations;
      };
    };
  };
}
