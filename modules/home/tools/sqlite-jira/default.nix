{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.tools.sqlite-jira;
in
{
  options.custom.tools.sqlite-jira = with types; {
    enable = mkBoolOpt false "Enable sqlite and jira-cli-go with libsqlite3 symlink";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      jira-cli-go
      sqlite
    ];

    home.file.".local/lib/libsqlite3.so".source = "${pkgs.sqlite.out}/lib/libsqlite3.so";
  };
}
