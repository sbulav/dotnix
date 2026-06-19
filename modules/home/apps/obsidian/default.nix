{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.custom.apps.obsidian;

  webdavSyncPlugin = pkgs.fetchFromGitHub {
    owner = "sbulav";
    repo = "obsidian-webdav-sync";
    rev = "43a32ecb6b156b3ed87efd18f309b7f15fbb6d2d";
    hash = "sha256-vy9yvPFTnPmVIDM+thhKli3/yOfFdbEKo45g0GJ99Uk=";
  };
in
{
  options.custom.apps.obsidian = {
    enable = mkEnableOption "Enable Obsidian note-taking app";

    vaultRelativePath = mkOption {
      type = types.str;
      default = "obsidian";
      description = "Path to the Obsidian vault relative to the home directory.";
    };

    useWebdavSyncFork = mkEnableOption "Use sbulav fork of WebDAV Sync plugin";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      obsidian
    ];

    home.file = mkIf cfg.useWebdavSyncFork {
      "${cfg.vaultRelativePath}/.obsidian/plugins/webdav-sync/manifest.json" = {
        source = "${webdavSyncPlugin}/manifest.json";
        force = true;
      };
      "${cfg.vaultRelativePath}/.obsidian/plugins/webdav-sync/main.js" = {
        source = "${webdavSyncPlugin}/main.js";
        force = true;
      };
      "${cfg.vaultRelativePath}/.obsidian/plugins/webdav-sync/styles.css" = {
        source = "${webdavSyncPlugin}/styles.css";
        force = true;
      };
    };
  };
}
