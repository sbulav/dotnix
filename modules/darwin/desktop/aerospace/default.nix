{
  lib,
  config,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.desktop.aerospace;
in
{
  options.custom.desktop.aerospace = {
    enable = mkBoolOpt false "Whether to enable the AeroSpace tiling window manager.";
  };

  config = mkIf cfg.enable {
    homebrew = {
      taps = [ "nikitabobko/tap" ];
      casks = [ "nikitabobko/tap/aerospace" ];
    };

    home-manager.users.${config.custom.user.name} = {
      home.file.".aerospace.toml".source = ./aerospace.toml;
    };
  };
}
