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
        background-color = "#FFFFFFee";
        border-color = "#00000033";
        border-size = "1";
        defaultTimeout = 5000;
        group-by = "app-name";
        progress-color = "source"; #07b5efee
        text-color = "#000000cc";
        anchor = "top-right";
        borderRadius = 5;
        font = "FiraCode Nerd Font 10";
        iconPath = "${pkgs.papirus-icon-theme}/share/icons/Papirus-Dark";
        icons = true;
        layer = "overlay";
        margin = "5";
        maxIconSize = 32;
      };
      criteria = {
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
