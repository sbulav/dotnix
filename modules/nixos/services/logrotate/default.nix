{
  config,
  lib,
  pkgs,
  namespace,
  ...
}: let
  inherit
    (lib)
    types
    mkIf
    foldl
    optionalString
    ;
  inherit (lib.${namespace}) mkBoolOpt mkOpt;

  cfg = config.${namespace}.services.logrotate;
in {
  options.${namespace}.services.logrotate = with types; {
    enable = mkBoolOpt false "Whether or not to configure logrotate.";
    logFiles = mkOpt (listOf str) ["/tank/traefik/logs/*.log"] "The list of log files to rotate";
  };

  config = mkIf cfg.enable {
    services.logrotate.settings = {
      header = {
        # general
        global = true;
        dateext = true;
        dateformat = "-%Y-%m-%d";
        nomail = true;
        missingok = true;
        copytruncate = true;

        # rotation frequency
        priority = 1;
        frequency = "daily";
        rotate = 7; # special value, means every 7 days
        minage = 3; # avoid removing logs that are less than 7 days old

        # compression
        compress = true; # lets compress logs to save space
        compresscmd = "${lib.getExe' pkgs.zstd "zstd"}";
        compressoptions = " -Xcompression-level 10";
        compressext = "zst";
        uncompresscmd = "${lib.getExe' pkgs.zstd "unzstd"}";
      };
      "multiple_paths" = {
        files = cfg.logFiles;
      };
    };
  };
}
