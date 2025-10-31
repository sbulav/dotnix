{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
let
  inherit (lib)
    types
    mkIf
    foldl
    optionalString
    ;
  inherit (lib.${namespace}) mkBoolOpt mkOpt;

  cfg = config.${namespace}.services.logrotate;
in
{
  options.${namespace}.services.logrotate = with types; {
    enable = mkBoolOpt false "Whether or not to configure logrotate.";
    logFiles = mkOpt (listOf str) [ "/tank/traefik/logs/*.log" ] "The list of log files to rotate";
  };

  config = mkIf cfg.enable {
    services.logrotate.settings = {
      "multiple_paths" = {
        files = cfg.logFiles;
        frequency = "daily";
        rotate = 7;
        dateext = true;
        dateformat = "-%Y-%m-%d";
        compress = true;
        compresscmd = "${pkgs.zstd}/bin/zstd";
        compressoptions = "-10";
        compressext = ".zst";
        uncompresscmd = "${pkgs.zstd}/bin/unzstd";
        copytruncate = true;
        missingok = true;
        notifempty = true;
      };
    };
  };
}
