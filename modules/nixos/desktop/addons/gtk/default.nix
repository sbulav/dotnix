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
  cfg = config.custom.desktop.addons.gtk;
in
{
  options.custom.desktop.addons.gtk = with types; {
    enable = mkBoolOpt false "Whether to enable GTK configuration.";

    home.config = mkIf cfg.enable {
      gtk.enable = true;
    };
  };
}
