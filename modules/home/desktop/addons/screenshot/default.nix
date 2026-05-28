{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.desktop.addons.screenshot;

  picturesDir =
    if config.xdg.userDirs.enable && config.xdg.userDirs.pictures != null then
      config.xdg.userDirs.pictures
    else
      "${config.home.homeDirectory}/Pictures";

  resolvedDir = if cfg.directory != null then cfg.directory else "${picturesDir}/Screenshots";

  wlCopy = "${lib.getExe' pkgs.wl-clipboard "wl-copy"}";

  getDateTime = lib.getExe (
    pkgs.writeShellScriptBin "screenshot-datetime" ''
      exec date +'${cfg.filenameFormat}'
    ''
  );

  freezeFlag = lib.optionalString cfg.freeze "--freeze";
  notifyFlag = lib.optionalString cfg.notify "--notify";

  # Helpers to build grimblast command strings tidily.
  # --freeze only matters for selection-based captures (area/active); skip for screen.
  mkFlags =
    target: extra:
    let
      useFreeze = cfg.freeze && (target == "area" || target == "active");
    in
    lib.concatStringsSep " " (
      lib.filter (s: s != "") (
        [
          (lib.optionalString useFreeze "--freeze")
          notifyFlag
        ]
        ++ extra
      )
    );

  gbCopy = target: "grimblast ${mkFlags target [ ]} copy ${target}";

  gbSave =
    target: "grimblast ${mkFlags target [ ]} save ${target} \"${resolvedDir}/$(${getDateTime}).png\"";

  # PNG to stdout. grimblast's `save TARGET -` defaults to PNG which satty
  # consumes directly. We avoid `--type`/`-t` here because the flag name
  # varies between grimblast forks and PNG is the safe lingua franca.
  gbStdoutPng =
    target:
    let
      useFreeze = cfg.freeze && (target == "area" || target == "active");
      flags = lib.optionalString useFreeze "--freeze";
    in
    "grimblast ${flags} save ${target} -";

  annotatorCmd =
    if cfg.annotator == "satty" then
      "satty --filename -"
    else if cfg.annotator == "swappy" then
      "swappy -f -"
    else
      null;

  hasAnnotate = annotatorCmd != null;

  mkAnnotate =
    target:
    "${gbStdoutPng target} | ${lib.getExe (
      pkgs.writeShellScriptBin "screenshot-annotate" ''
        exec ${annotatorCmd}
      ''
    )}";

  # Public command attrset consumed by other modules (hyprland, wlr-which-key).
  commands = {
    region = {
      clipboard = gbCopy "area";
      file = gbSave "area";
    }
    // lib.optionalAttrs hasAnnotate { annotate = mkAnnotate "area"; };

    window = {
      clipboard = gbCopy "active";
      file = gbSave "active";
    }
    // lib.optionalAttrs hasAnnotate { annotate = mkAnnotate "active"; };

    screen = {
      clipboard = gbCopy "screen";
      file = gbSave "screen";
    }
    // lib.optionalAttrs hasAnnotate { annotate = mkAnnotate "screen"; };
  };

  # Relative path inside $HOME for the .keep file (skip if dir is outside $HOME).
  homePrefix = config.home.homeDirectory + "/";
  relScreenshotDir = lib.removePrefix homePrefix resolvedDir;
  isInsideHome = lib.hasPrefix homePrefix resolvedDir;
in
{
  options.custom.desktop.addons.screenshot = with types; {
    enable = mkBoolOpt false "Whether to enable the screenshot addon (grimblast + annotator).";

    annotator = mkOpt (enum [
      "satty"
      "swappy"
      "none"
    ]) "satty" "Annotation tool. 'none' disables annotation entirely.";

    captureBackend = mkOpt (enum [ "grimblast" ]) "grimblast" "Screenshot capture tool.";

    directory = mkOpt (nullOr str) null ''
      Directory where file screenshots are saved. Defaults to
      `${"$"}{xdg.userDirs.pictures}/Screenshots` (or `~/Pictures/Screenshots`
      when xdg.userDirs is disabled).
    '';

    freeze = mkBoolOpt true "Freeze the screen during region/window selection (--freeze).";
    notify = mkBoolOpt true "Show notification on save/copy (--notify).";

    filenameFormat =
      mkOpt str "ss_%Y%m%d_%H%M%S"
        "date(1) format for screenshot filenames (without extension).";

    commands = mkOpt (attrsOf (attrsOf str)) { } ''
      Read-only map of generated screenshot commands. Consumed by other
      modules (hyprland binds, wlr-which-key). Structure:
        commands.<region|window|screen>.<clipboard|file|annotate>
      The `annotate` keys are omitted when `annotator = "none"`.
    '';
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isLinux;
        message = "custom.desktop.addons.screenshot is Linux-only.";
      }
    ];

    home.packages =
      with pkgs;
      [
        grimblast
        wl-clipboard
      ]
      ++ lib.optional (cfg.annotator == "swappy") swappy;
    # satty is installed via programs.satty.enable below.

    # Pre-create the screenshots directory inside $HOME.
    home.file = lib.mkIf isInsideHome {
      "${relScreenshotDir}/.keep".text = "";
    };

    programs.satty = mkIf (cfg.annotator == "satty") {
      enable = true;
      settings = {
        general = {
          copy-command = wlCopy;
          output-filename = "${resolvedDir}/satty-%Y-%m-%d_%H:%M:%S.png";
          save-after-copy = false;
          default-hide-toolbars = false;
          early-exit = true;
          # Enter -> save to file + clipboard, then exit. Escape -> exit silently.
          actions-on-enter = [
            "save-to-clipboard"
            "save-to-file"
            "exit"
          ];
          actions-on-escape = [ "exit" ];
        };
      };
    };

    custom.desktop.addons.screenshot.commands = commands;
  };
}
