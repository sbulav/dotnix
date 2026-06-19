{
  config,
  lib,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.tools.homebrew;
in
{
  options.custom.tools.homebrew = {
    enable = mkBoolOpt false "Whether to enable Homebrew management.";
  };

  config = mkIf cfg.enable {
    homebrew = {
      enable = true;

      global.brewfile = true;

      onActivation = {
        autoUpdate = true;
        cleanup = "uninstall";
        upgrade = true;
      };

      casks = [
        "raycast"
        "xnviewmp"
        "colemak-dh"
      ];
    };
  };
}
