{
  lib,
  config,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.apps.obsidian;
in
{
  options.custom.apps.obsidian = {
    enable = mkBoolOpt false "Whether to enable Obsidian note-taking app.";
  };

  config = mkIf cfg.enable {
    homebrew.casks = [ "obsidian" ];
  };
}
