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
  cfg = config.custom.desktop.addons.mako;
in
{
  options.custom.desktop.addons.mako = with types; {
    enable = mkBoolOpt false "Whether to enable Mako in Sway.";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      libnotify
    ];
    services.mako = {
      enable = true;
      settings = {
        anchor = "top-right";
        border-radius = 5;
        border-size = "1";
        default-timeout = 5000;
        max-history = 5;
        group-by = "app-name";
        icons = true;
        layer = "overlay";
        margin = "5";
        max-icon-size = 32;
        "urgency=high" = {
          default-timeout = 0;
        };
      };
    };
  };
}
