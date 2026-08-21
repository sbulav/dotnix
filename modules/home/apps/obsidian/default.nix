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

  syncEngineVersion = "3.1.0";
  syncEngineBaseUrl = "https://github.com/hesprs/sync-engine/releases/download/${syncEngineVersion}";
  syncEnginePlugin = {
    manifest = pkgs.fetchurl {
      url = "${syncEngineBaseUrl}/manifest.json";
      hash = "sha256-/aJoX22+xQ34+j56NpyEyalWIGtE53YazBZYMSfh8N8=";
    };
    main = pkgs.fetchurl {
      url = "${syncEngineBaseUrl}/main.js";
      hash = "sha256-tMhn6N++7mKGXE5cfUPxRUqNxsSG79luoYyVZghPAvo=";
    };
    styles = pkgs.fetchurl {
      url = "${syncEngineBaseUrl}/styles.css";
      hash = "sha256-c9FwSmJZfrmWWGL+VbjguOVVla1y4r2zaWMN3KrVGLo=";
    };
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

    syncEngine.enable = mkEnableOption "Install the Sync Engine Obsidian plugin";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      obsidian
    ];

    home.file = mkIf cfg.syncEngine.enable {
      "${cfg.vaultRelativePath}/.obsidian/plugins/sync-engine/manifest.json" = {
        source = syncEnginePlugin.manifest;
        force = true;
      };
      "${cfg.vaultRelativePath}/.obsidian/plugins/sync-engine/main.js" = {
        source = syncEnginePlugin.main;
        force = true;
      };
      "${cfg.vaultRelativePath}/.obsidian/plugins/sync-engine/styles.css" = {
        source = syncEnginePlugin.styles;
        force = true;
      };
    };
  };
}
