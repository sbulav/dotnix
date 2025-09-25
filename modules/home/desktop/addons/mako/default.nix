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
        background-color = "#0d1117ee";
        border-color = "#00000033";
        border-radius = 5;
        border-size = "1";
        default-timeout = 5000;
        max-history = 5;
        font = "FiraCode Nerd Font 10";
        group-by = "app-name";
        icon-path = "${pkgs.papirus-icon-theme}/share/icons/Papirus-Dark";
        icons = true;
        layer = "overlay";
        margin = "5";
        progress-color = "source #00d4aaee"; #07b5efee
        text-color = "#c9d1d9cc";
        max-icon-size = 32;
        "urgency=high" = {
          border-color = "#ff6b6bee";
          default-timeout = 0;
        };
        "urgency=normal" = {
          border-color = "#7c3aed33";
        };
        "urgency=low" = {
          border-color = "#00d4aa33";
        };
      };
    };
  };
}
