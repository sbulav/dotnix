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

  syncEngineVersion = "3.4.3";
  syncEngineBaseUrl = "https://github.com/hesprs/sync-engine/releases/download/${syncEngineVersion}";
  syncEnginePlugin = {
    manifest = pkgs.fetchurl {
      url = "${syncEngineBaseUrl}/manifest.json";
      hash = "sha256-f/SoMtKWLacNrIPe9ZThkBQ2d9AmWFmPiHcvMkiRaMM=";
    };
    main = pkgs.fetchurl {
      url = "${syncEngineBaseUrl}/main.js";
      hash = "sha256-7f+BP4TVbnEd8UA8nU1YTEQ0JNjoRpemKNj/Tla3EDg=";
    };
    styles = pkgs.fetchurl {
      url = "${syncEngineBaseUrl}/styles.css";
      hash = "sha256-uzMnTnVICT7Zg3XP6Z1QGSLI7tSHO84GMDLA464zA20=";
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
