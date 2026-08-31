{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with lib.custom;
let
  cfg = config.custom.apps.voxtype;

  # Same pinned model the whisper-dictation setup used; voxtype's `model`
  # key accepts an absolute path, so the store path keeps it declarative
  # instead of `voxtype setup --download` imperative state.
  defaultModel = pkgs.fetchurl {
    name = "ggml-large-v3-turbo-q5_0.bin";
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin?download=true";
    hash = "sha256-OUIhcJzVrR9AxG5gMcphvOiJMebgiMGIKUxtWlX/p+I=";
  };

  # Parakeet needs the ONNX export with exactly these file names; voxtype
  # resolves encoder-model.onnx.data relative to the model_path directory,
  # so a linkFarm of pinned files stands in for `voxtype setup --download`.
  parakeetFile =
    name: hash:
    pkgs.fetchurl {
      inherit name hash;
      url = "https://huggingface.co/istupakov/parakeet-tdt-0.6b-v3-onnx/resolve/main/${name}?download=true";
    };

  defaultParakeetModel = pkgs.linkFarm "parakeet-tdt-0.6b-v3" (
    mapAttrsToList (name: hash: {
      inherit name;
      path = parakeetFile name hash;
    }) parakeetHashes
  );

  parakeetHashes = {
    "encoder-model.onnx" = "sha256-mKdLIbTMABfB5wMDGaSpb0qVBuUPBwjzpRbQKnfJa7E=";
    "encoder-model.onnx.data" = "sha256-miLTcsUUVcNPE0BdolILrvtxJb0WmBOXVhQj7TLSTzY=";
    "decoder_joint-model.onnx" = "sha256-6Xjd9miFJxgsEP3i60uDBoQhZImF7yP3qGvnMr6HBsE=";
    "vocab.txt" = "sha256-1YVEZ56kvGrFY9H1Ret9R0vWz6Rn8KbiwdwcfTfjw10=";
    "config.json" = "sha256-ZmkDx2uXmMrywhCv1PbNYLCKjb+YAOyNejvA0hSKxGY=";
  };

  # CPU-only by default in nixpkgs; Vulkan is a cache-miss override our CI
  # cachix absorbs. unstable carries 0.7.x with the split engine features.
  # ONNX (parakeet et al.) is only pulled in when that engine is selected.
  defaultPackage = pkgs.unstable.voxtype.override {
    vulkanSupport = true;
    onnxSupport = cfg.engine == "parakeet";
  };

  tomlFormat = pkgs.formats.toml { };

  settings = recursiveUpdate (
    {
      # Required for `voxtype record toggle`/`status` from compositor binds.
      state_file = "auto";
      # Push-to-talk comes from Hyprland binds below, not voxtype's own
      # evdev listener (which would need the input group).
      hotkey.enabled = false;
      audio = {
        device = "default";
        sample_rate = 16000;
        pause_media = true;
        # Required field in 0.7.x (no serde default): max recording length.
        max_duration_secs = 60;
      };
      whisper = {
        model = "${cfg.model}";
        language = cfg.language;
      };
      output = {
        mode = cfg.outputMode;
        fallback_to_clipboard = true;
      }
      // optionalAttrs (cfg.outputMode == "paste") {
        paste_keys = cfg.pasteKeys;
      };
    }
    # Only emitted when selected: a [parakeet] section on a non-ONNX build
    # is at best dead config. Parakeet v3 language-detects on its own; the
    # whisper table stays as the one-line rollback.
    // optionalAttrs (cfg.engine == "parakeet") {
      engine = "parakeet";
      # Key is `model`, not `model_path` (0.7.x schema).
      parakeet.model = "${cfg.parakeet.model}";
    }
  ) cfg.settings;

  voxtypeBin = "${cfg.package}/bin/voxtype";

  # Passed to the daemon explicitly via -c so a config change also changes
  # the unit file: HM restarts changed units, and voxtype reads config only
  # at startup — without this, activation silently leaves the old daemon
  # running with stale settings.
  configFile = tomlFormat.generate "voxtype-config.toml" settings;
in
{
  options.custom.apps.voxtype = {
    enable = mkBoolOpt false "Whether to enable voxtype push-to-talk dictation.";

    package = mkOpt types.package defaultPackage "Voxtype package (default: unstable with Vulkan).";

    engine = mkOpt (types.enum [
      "whisper"
      "parakeet"
    ]) "whisper" "Speech engine.";

    model = mkOpt types.path defaultModel "Path to a whisper.cpp GGML model (whisper engine).";

    parakeet.model =
      mkOpt types.path defaultParakeetModel
        "Directory with the Parakeet ONNX model files (parakeet engine).";

    language = mkOpt (types.either types.str (types.listOf types.str)) "auto" ''
      Whisper language code, or a constrained auto-detect list. A short
      clip spoken in one of your languages is routinely misdetected under
      unconstrained "auto"; a two-language list pins detection to the set
      you actually speak (e.g. [ "en" "ru" ]).
    '';

    outputMode =
      mkOpt
        (types.enum [
          "type"
          "clipboard"
          "paste"
        ])
        "type"
        ''
          How transcribed text reaches the focused window. "type" synthesizes
          keystrokes via wtype — broken in XWayland windows when the compositor
          layout is not us, and lossy in fast Electron apps. "paste" goes
          through the clipboard atomically and is layout-independent;
          "clipboard" copies only (manual paste).
        '';

    pasteKeys = mkOpt types.str "ctrl+shift+v" ''
      Keystroke for outputMode = "paste". ctrl+shift+v reads the clipboard in
      terminals and pastes plain text in GUI apps; shift+insert reads the
      primary selection in WezTerm and therefore misses voxtype's clipboard.
    '';

    pushToTalkBind =
      mkOpt (types.nullOr types.str) "ALT + slash"
        "Hyprland chord held to dictate (hl.bind key string). null to disable.";

    toggleBind =
      mkOpt (types.nullOr types.str) null
        "Hyprland chord toggling dictation on/off (hl.bind key string). null to disable.";

    settings = mkOpt (types.attrsOf types.anything) { } "Extra voxtype config merged into config.toml.";
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];

    xdg.configFile."voxtype/config.toml".source = configFile;

    systemd.user.services.voxtype = {
      Unit = {
        Description = "Voxtype dictation daemon";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
        ConditionEnvironment = "WAYLAND_DISPLAY";
      };
      Service = {
        ExecStart = "${voxtypeBin} -c ${configFile}";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    custom.desktop.hyprland.keybindings.extra =
      optionals (cfg.pushToTalkBind != null) [
        ''hl.bind(${builtins.toJSON cfg.pushToTalkBind}, hl.dsp.exec_cmd("${voxtypeBin} record start"), { description = "Start dictation (push-to-talk)" })''
        ''hl.bind(${builtins.toJSON cfg.pushToTalkBind}, hl.dsp.exec_cmd("${voxtypeBin} record stop"), { release = true, description = "Stop dictation (push-to-talk)" })''
      ]
      ++ optionals (cfg.toggleBind != null) [
        ''hl.bind(${builtins.toJSON cfg.toggleBind}, hl.dsp.exec_cmd("${voxtypeBin} record toggle"), { description = "Toggle dictation" })''
      ];
  };
}
