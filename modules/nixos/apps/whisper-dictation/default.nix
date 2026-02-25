{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
with lib.custom;
let
  inherit (lib)
    getOutput
    mkIf
    optionalString
    types
    ;
  cfg = config.custom.apps.whisper-dictation;

  socketPath = cfg.ydotoolSocketPath;
  daemonExec = "${cfg.package}/bin/whisper-dictation --language ${cfg.language}${
    optionalString (cfg.model != "") " --model ${cfg.model}"
  }";
  giTypelibPath = lib.concatStringsSep ":" [
    "${getOutput "out" pkgs.harfbuzz}/lib/girepository-1.0"
    "${getOutput "out" pkgs.pango}/lib/girepository-1.0"
    "${getOutput "out" pkgs.cairo}/lib/girepository-1.0"
    "${getOutput "out" pkgs.gdk-pixbuf}/lib/girepository-1.0"
    "${getOutput "out" pkgs.graphene}/lib/girepository-1.0"
    "${getOutput "out" pkgs.gtk4}/lib/girepository-1.0"
    "${getOutput "out" pkgs.glib}/lib/girepository-1.0"
  ];
in
{
  options.custom.apps.whisper-dictation = {
    enable = mkBoolOpt false "Whether to enable Whisper Dictation.";

    package =
      mkOpt types.package inputs.whisper-dictation.packages.${pkgs.stdenv.hostPlatform.system}.default
        "Whisper Dictation package to install.";

    autoStart = mkBoolOpt true "Whether to auto-start the daemon on login.";

    language = mkOpt types.str "auto" "Language code for dictation (auto, en, it, etc.).";

    model = mkOpt types.str "base" "Whisper model to use (tiny, base, small, medium, large).";

    hotkey = {
      modifiers = mkOpt (types.listOf types.str) [
        "super"
      ] "Hotkey modifiers (super, ctrl, alt, shift).";
      key = mkOpt types.str "period" "Hotkey key (period, comma, space, slash, semicolon).";
    };

    ydotoolSocketPath = mkOpt types.str "/run/user/%U/.ydotool_socket" "Path for ydotool socket.";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
      pkgs.ydotool
      pkgs.procps
      pkgs.harfbuzz
      pkgs.pango
      pkgs.cairo
      pkgs.gdk-pixbuf
      pkgs.graphene
      pkgs.gtk4
    ];

    home.file.".local/share/whisper/models/.keep".text = "";

    home.configFile."whisper-dictation/config.yaml".text = ''
      hotkey:
        modifiers: ${builtins.toJSON cfg.hotkey.modifiers}
        key: ${builtins.toJSON cfg.hotkey.key}
      whisper:
        language: ${cfg.language}
        model: ${cfg.model}
    '';

    systemd.user.services.ydotoold = {
      enable = cfg.autoStart;
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.ydotool}/bin/ydotoold --socket-path=${socketPath} --socket-perm=0600";
        Restart = "on-failure";
      };
    };

    systemd.user.services.whisper-dictation = {
      enable = cfg.autoStart;
      wantedBy = [ "graphical-session.target" ];
      after = [
        "graphical-session.target"
        "ydotoold.service"
      ];
      wants = [ "ydotoold.service" ];
      path = [ pkgs.procps ];
      serviceConfig = {
        ExecStart = daemonExec;
        Restart = "on-failure";
        Environment = [
          "GI_TYPELIB_PATH=${giTypelibPath}"
          "YDOTOOL_SOCKET=${socketPath}"
        ];
      };
    };
  };
}
