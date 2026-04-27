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
  c = config.custom.theme.colors;
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
        background-color = "#${c.panel}ee";
        border-color = "#${c.violet}66";
        border-radius = 5;
        border-size = "1";
        default-timeout = 5000;
        max-history = 5;
        font = "JetBrainsMono Nerd Font 10";
        group-by = "app-name";
        icon-path = "${pkgs.papirus-icon-theme}/share/icons/Papirus-Dark";
        icons = true;
        layer = "overlay";
        margin = "5";
        progress-color = "source #${c.cyan}ee";
        text-color = "#${c.text}cc";
        max-icon-size = 32;
        "urgency=high" = {
          border-color = "#${c.pink}ee";
          default-timeout = 0;
        };
        "urgency=normal" = {
          border-color = "#${c.violet}66";
        };
        "urgency=low" = {
          border-color = "#${c.mint}66";
        };
      };
    };
  };
}
