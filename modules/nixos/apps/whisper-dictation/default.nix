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
    escapeShellArgs
    mkIf
    types
    ;
  cfg = config.custom.apps.whisper-dictation;

  socketPath = cfg.ydotoolSocketPath;

  defaultModel = pkgs.fetchurl {
    name = "ggml-large-v3-turbo-q5_0.bin";
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin?download=true";
    hash = "sha256-OUIhcJzVrR9AxG5gMcphvOiJMebgiMGIKUxtWlX/p+I=";
  };

  whisperCpp = pkgs.unstable.whisper-cpp-vulkan.override {
    withFFmpegSupport = false;
    withSDL = false;
  };

  python = pkgs.python3;
  pythonEnv = python.withPackages (
    ps: with ps; [
      evdev
      pyyaml
    ]
  );

  whisper-dictation = pkgs.stdenv.mkDerivation {
    pname = "whisper-dictation";
    version = "0.2.0-whisper-cpp";
    src = inputs.whisper-dictation;

    nativeBuildInputs = [ pkgs.makeWrapper ];

    postPatch = ''
      cp ${./transcriber.py} src/whisper_dictation/transcriber.py
      cp ${./paste.py} src/whisper_dictation/paste.py
      cp ${./recorder.py} src/whisper_dictation/recorder.py
      cp ${./ui.py} src/whisper_dictation/ui.py
    '';

    dontBuild = true;

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin $out/lib/whisper-dictation
      cp -r src/whisper_dictation $out/lib/whisper-dictation/

      makeWrapper ${pythonEnv}/bin/python3 $out/bin/whisper-dictation \
        --add-flags "-m whisper_dictation" \
        --set PYTHONPATH "$out/lib/whisper-dictation" \
        --prefix PATH : ${
          lib.makeBinPath [
            pkgs.libnotify
            pkgs.pipewire
            pkgs.procps
            pkgs.wl-clipboard
            pkgs.wtype
            pkgs.ydotool
          ]
        }

      runHook postInstall
    '';

    meta = with lib; {
      description = "Local push-to-talk speech-to-text dictation (whisper.cpp backend)";
      homepage = "https://github.com/jacopone/whisper-dictation";
      license = licenses.mit;
      platforms = platforms.linux;
    };
  };

  daemonExec = escapeShellArgs [
    "${cfg.package}/bin/whisper-dictation"
    "--language"
    cfg.language
  ];

  serverExec = escapeShellArgs [
    "${cfg.server.package}/bin/whisper-server"
    "--model"
    (toString cfg.model)
    "--host"
    cfg.server.host
    "--port"
    (toString cfg.server.port)
    "--language"
    cfg.language
    "--threads"
    (toString cfg.server.threads)
    "--beam-size"
    (toString cfg.beamSize)
    "--flash-attn"
  ];
in
{
  options.custom.apps.whisper-dictation = {
    enable = mkBoolOpt false "Whether to enable Whisper Dictation.";

    package = mkOpt types.package whisper-dictation "Whisper Dictation package.";

    autoStart = mkBoolOpt true "Whether to auto-start the daemon on login.";

    language = mkOpt types.str "auto" "Language code (auto, en, ru, it, ...).";

    model = mkOpt types.path defaultModel "Path to a whisper.cpp GGML model.";

    beamSize = mkOpt types.int 5 "Beam size for decoding. Higher = better, slower.";

    initialPrompt =
      mkOpt types.str ""
        "Initial prompt to bias vocabulary (names, jargon). Empty to disable.";

    server = {
      package = mkOpt types.package whisperCpp "whisper.cpp server package.";
      host = mkOpt types.str "127.0.0.1" "Address for the local transcription server.";
      port = mkOpt types.port 8178 "Port for the local transcription server.";
      threads = mkOpt types.int 4 "CPU threads used by whisper.cpp.";
    };

    hotkey = {
      modifiers = mkOpt (types.listOf types.str) [
        "super"
      ] "Hotkey modifiers (super, ctrl, alt, shift).";
      key = mkOpt types.str "period" "Hotkey key (period, comma, space, slash, semicolon).";
    };

    paste = {
      method = mkOpt types.str "clipboard" "Paste method (clipboard or type).";
      shortcut = {
        modifiers = mkOpt (types.listOf types.str) [ "shift" ] "Paste shortcut modifiers.";
        key = mkOpt types.str "insert" "Paste shortcut key.";
      };
    };

    ydotoolSocketPath = mkOpt types.str "/run/user/%U/.ydotool_socket" "Path for ydotool socket.";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
      cfg.server.package
      pkgs.pipewire
      pkgs.procps
      pkgs.wl-clipboard
      pkgs.wtype
      pkgs.ydotool
    ];

    home.configFile."whisper-dictation/config.yaml".text = ''
      hotkey:
        modifiers: ${builtins.toJSON cfg.hotkey.modifiers}
        key: ${builtins.toJSON cfg.hotkey.key}
      paste:
        method: ${builtins.toJSON cfg.paste.method}
        shortcut:
          modifiers: ${builtins.toJSON cfg.paste.shortcut.modifiers}
          key: ${builtins.toJSON cfg.paste.shortcut.key}
      whisper:
        server_url: ${builtins.toJSON "http://${cfg.server.host}:${toString cfg.server.port}/inference"}
        language: ${builtins.toJSON cfg.language}
        beam_size: ${toString cfg.beamSize}
        initial_prompt: ${builtins.toJSON cfg.initialPrompt}
    '';

    systemd.user.services.ydotoold = {
      enable = cfg.autoStart;
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.ydotool}/bin/ydotoold --socket-path=${socketPath} --socket-perm=0600";
        Restart = "on-failure";
      };
    };

    systemd.user.services.whisper-dictation-server = {
      enable = cfg.autoStart;
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = serverExec;
        Restart = "on-failure";
        RestartSec = "2s";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
      };
    };

    systemd.user.services.whisper-dictation = {
      enable = cfg.autoStart;
      wantedBy = [ "graphical-session.target" ];
      after = [
        "graphical-session.target"
        "whisper-dictation-server.service"
        "ydotoold.service"
      ];
      wants = [
        "whisper-dictation-server.service"
        "ydotoold.service"
      ];
      path = [
        pkgs.libnotify
        pkgs.pipewire
        pkgs.procps
        pkgs.wl-clipboard
        pkgs.wtype
        pkgs.ydotool
      ];
      serviceConfig = {
        ExecStart = daemonExec;
        Restart = "on-failure";
        RestartSec = "2s";
        Environment = [ "YDOTOOL_SOCKET=${socketPath}" ];
      };
    };
  };
}
