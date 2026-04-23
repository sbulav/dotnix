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

  # Scoped CUDA build: only the C++ ctranslate2 rebuilds against CUDA.
  # Everything else keeps its cached, CPU-only binary.
  ct2cppCuda = pkgs.unstable.ctranslate2.override { withCUDA = true; };

  python = pkgs.unstable.python312;
  pythonEnv = python.withPackages (
    ps: with ps; [
      (faster-whisper.override {
        ctranslate2 = ctranslate2.override { ctranslate2-cpp = ct2cppCuda; };
      })
      evdev
      pygobject3
      pyaudio
      numpy
      scipy
      pyyaml
    ]
  );

  giTypelibPath = lib.concatStringsSep ":" [
    "${getOutput "out" pkgs.harfbuzz}/lib/girepository-1.0"
    "${getOutput "out" pkgs.pango}/lib/girepository-1.0"
    "${getOutput "out" pkgs.cairo}/lib/girepository-1.0"
    "${getOutput "out" pkgs.gdk-pixbuf}/lib/girepository-1.0"
    "${getOutput "out" pkgs.graphene}/lib/girepository-1.0"
    "${getOutput "out" pkgs.gtk4}/lib/girepository-1.0"
    "${getOutput "out" pkgs.glib}/lib/girepository-1.0"
    "${pkgs.gobject-introspection}/lib/girepository-1.0"
  ];

  whisper-dictation = pkgs.stdenv.mkDerivation {
    pname = "whisper-dictation";
    version = "0.1.0-faster-whisper";
    src = inputs.whisper-dictation;

    nativeBuildInputs = [ pkgs.makeWrapper ];

    buildInputs = [
      pythonEnv
      pkgs.ffmpeg
      pkgs.ydotool
      pkgs.libnotify
      pkgs.gtk4
      pkgs.gobject-introspection
    ];

    postPatch = ''
      cp ${./transcriber.py} src/whisper_dictation/transcriber.py
      cp ${./paste.py} src/whisper_dictation/paste.py
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
            pkgs.ffmpeg
            pkgs.ydotool
            pkgs.libnotify
            pkgs.wl-clipboard
            pkgs.wtype
            pkgs.procps
          ]
        } \
        --prefix GI_TYPELIB_PATH : "${giTypelibPath}"

      runHook postInstall
    '';

    meta = with lib; {
      description = "Local push-to-talk speech-to-text dictation (faster-whisper backend)";
      homepage = "https://github.com/jacopone/whisper-dictation";
      license = licenses.mit;
      platforms = platforms.linux;
    };
  };

  daemonExec = "${whisper-dictation}/bin/whisper-dictation --language ${cfg.language}${
    optionalString (cfg.model != "") " --model ${cfg.model}"
  }";
in
{
  options.custom.apps.whisper-dictation = {
    enable = mkBoolOpt false "Whether to enable Whisper Dictation.";

    package = mkOpt types.package whisper-dictation "Whisper Dictation package.";

    autoStart = mkBoolOpt true "Whether to auto-start the daemon on login.";

    language = mkOpt types.str "auto" "Language code (auto, en, ru, it, ...).";

    model = mkOpt types.str "large-v3-turbo" "faster-whisper model name (tiny, base, small, medium, large-v3, large-v3-turbo, distil-large-v3).";

    device = mkOpt types.str "cuda" "Compute device: cuda | cpu | auto.";

    computeType = mkOpt types.str "float16" "CTranslate2 compute type (float16 | int8_float16 | int8 | float32).";

    beamSize = mkOpt types.int 5 "Beam size for decoding. Higher = better, slower.";

    initialPrompt = mkOpt types.str "" "Initial prompt to bias vocabulary (names, jargon). Empty to disable.";

    vad = {
      enable = mkBoolOpt true "Use Silero VAD to skip silence before decoding.";
      minSilenceMs = mkOpt types.int 500 "Min silence duration (ms) to cut.";
      speechPadMs = mkOpt types.int 200 "Padding around detected speech (ms).";
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
      pkgs.ydotool
      pkgs.procps
      pkgs.wl-clipboard
      pkgs.wtype
      pkgs.ffmpeg
    ];

    home.file.".cache/whisper-dictation/.keep".text = "";

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
        language: ${cfg.language}
        model: ${cfg.model}
        device: ${cfg.device}
        compute_type: ${cfg.computeType}
        beam_size: ${toString cfg.beamSize}
        initial_prompt: ${builtins.toJSON cfg.initialPrompt}
        vad:
          enable: ${lib.boolToString cfg.vad.enable}
          min_silence_ms: ${toString cfg.vad.minSilenceMs}
          speech_pad_ms: ${toString cfg.vad.speechPadMs}
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
      path = [
        pkgs.procps
        pkgs.ydotool
        pkgs.wl-clipboard
        pkgs.wtype
        pkgs.ffmpeg
      ];
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
