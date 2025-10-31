{
  config,
  lib,
  namespace,
  ...
}:
let
  inherit (lib) mkDefault;
  inherit (lib.${namespace}) mkBoolOpt enabled;

  cfg = config.suites.games;
in
{
  options.suites.games = {
    enable = mkBoolOpt false "Whether or not to enable common games configuration.";
  };

  config = lib.mkIf cfg.enable {
    custom = {
      desktop = {
        addons = {
          gamemode = mkDefault enabled;
          gamescope = mkDefault enabled;
        };
      };
      apps = {
        steam = mkDefault enabled;
      };
    };
  };
}
