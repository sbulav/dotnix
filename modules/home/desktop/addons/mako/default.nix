{
  options,
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom; let
  cfg = config.custom.desktop.addons.mako;
in {
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
        background-color = "#FFFFFFee";
        border-color = "#00000033";
        border-radius = 5;
        border-size = "1";
        default-timeout = 5000;
        font = "FiraCode Nerd Font 10";
        group-by = "app-name";
        icon-path = "${pkgs.papirus-icon-theme}/share/icons/Papirus-Dark";
        icons = true;
        layer = "overlay";
        margin = "5";
        progress-color = "source #07b5efee"; #07b5efee
        text-color = "#000000cc";
        max-icon-size = 32;
        "urgency=high" = {
          border-color = "#394b70";
          default-timeout = 0;
        };
        "urgency=normal" = {
          border-color = "#00000033";
        };
        "urgency=low" = {
          border-color = "#ff757f";
        };
      };
    };
  };
}
