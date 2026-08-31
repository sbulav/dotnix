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
    "encoder-model.onnx" = "";
    "encoder-model.onnx.data" = "";
    "decoder_joint-model.onnx" = "";
    "vocab.txt" = "";
    "config.json" = "";
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
      };
      whisper = {
        model = "${cfg.model}";
        language = cfg.language;
      };
      output = {
        mode = "type";
        fallback_to_clipboard = true;
      };
    }
    # Only emitted when selected: a [parakeet] section on a non-ONNX build
    # is at best dead config. Parakeet v3 language-detects on its own; the
    # whisper table stays as the one-line rollback.
    // optionalAttrs (cfg.engine == "parakeet") {
      engine = "parakeet";
      parakeet.model_path = "${cfg.parakeet.model}";
    }
  ) cfg.settings;

  voxtypeBin = "${cfg.package}/bin/voxtype";
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

    language = mkOpt types.str "auto" "Whisper language code (auto, en, ru, it, ...).";

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

    xdg.configFile."voxtype/config.toml".source = tomlFormat.generate "voxtype-config.toml" settings;

    systemd.user.services.voxtype = {
      Unit = {
        Description = "Voxtype dictation daemon";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
        ConditionEnvironment = "WAYLAND_DISPLAY";
      };
      Service = {
        ExecStart = voxtypeBin;
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
