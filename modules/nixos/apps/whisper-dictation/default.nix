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

    package = mkOpt types.package (
      inputs.whisper-dictation.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs
      (old: {
        postPatch = (old.postPatch or "") + ''
          python - <<'PY'
          from pathlib import Path

          lines = [
              '"""Text pasting module using ydotool"""',
              "",
              "import logging",
              "import subprocess",
              "import time",
              "",
              "from evdev import ecodes",
              "",
              "logger = logging.getLogger(__name__)",
              "",
              "",
              "class TextPaster:",
              "    \"\"\"Pastes text into active window using ydotool\"\"\"",
              "",
              "    def __init__(self, config):",
              "        self.config = config",
              "        self._check_ydotool()",
              "        self._paste_method = self.config.get(\"paste.method\", \"type\")",
              "        self._paste_modifiers = self.config.get(\"paste.shortcut.modifiers\", [\"shift\"])",
              "        self._paste_key = self.config.get(\"paste.shortcut.key\", \"insert\")",
              "",
              "        self._modifier_map = {",
              "            \"super\": ecodes.KEY_LEFTMETA,",
              "            \"ctrl\": ecodes.KEY_LEFTCTRL,",
              "            \"alt\": ecodes.KEY_LEFTALT,",
              "            \"shift\": ecodes.KEY_LEFTSHIFT,",
              "        }",
              "",
              "        self._key_map = {",
              "            \"insert\": ecodes.KEY_INSERT,",
              "            \"v\": ecodes.KEY_V,",
              "        }",
              "",
              "    def _check_ydotool(self):",
              "        \"\"\"Check if ydotool daemon is running\"\"\"",
              "        try:",
              "            result = subprocess.run([\"pgrep\", \"-x\", \"ydotoold\"], capture_output=True)",
              "            if result.returncode != 0:",
              "                logger.warning(",
              "                    \"ydotool daemon not running. Start with: systemctl --user start ydotool\"",
              "                )",
              "        except Exception as e:",
              "            logger.error(f\"Error checking ydotool: {e}\")",
              "",
              "    def paste(self, text: str):",
              "        \"\"\"Paste text into active window\"\"\"",
              "        if not text:",
              "            return",
              "",
              "        logger.info(f\"Pasting text: {text[:50]}...\")",
              "",
              "        try:",
              "            # Small delay to ensure window focus",
              "            time.sleep(self.config.get(\"typing.start_delay\", 0.3))",
              "",
              "            if self._paste_method == \"clipboard\":",
              "                subprocess.run([\"wl-copy\"], input=text, text=True, check=True)",
              "",
              "                modifiers = [",
              "                    self._modifier_map[m]",
              "                    for m in self._paste_modifiers",
              "                    if m in self._modifier_map",
              "                ]",
              "                keycode = self._key_map.get(self._paste_key)",
              "",
              "                if keycode is None:",
              "                    raise ValueError(f\"Unsupported paste key: {self._paste_key}\")",
              "",
              "                key_events = []",
              "                for code in modifiers:",
              "                    key_events.append(f\"{code}:1\")",
              "",
              "                key_events.append(f\"{keycode}:1\")",
              "                key_events.append(f\"{keycode}:0\")",
              "",
              "                for code in reversed(modifiers):",
              "                    key_events.append(f\"{code}:0\")",
              "",
              "                subprocess.run([\"ydotool\", \"key\", *key_events], check=True)",
              "            else:",
              "                # Use wtype to type text (respects keyboard layout)",
              "                subprocess.run(",
              "                    [\"wtype\", text],",
              "                    check=True,",
              "                )",
              "",
              "            logger.info(\"Text pasted successfully\")",
              "",
              "        except subprocess.CalledProcessError as e:",
              "            logger.error(f\"ydotool failed: {e}\")",
              "            raise",
              "        except Exception as e:",
              "            logger.error(f\"Error pasting text: {e}\")",
              "            raise",
          ]

          Path("src/whisper_dictation/paste.py").write_text("\n".join(lines) + "\n")
          PY
        '';
      })
    ) "Whisper Dictation package to install.";

    autoStart = mkBoolOpt true "Whether to auto-start the daemon on login.";

    language = mkOpt types.str "auto" "Language code for dictation (auto, en, it, etc.).";

    model = mkOpt types.str "base" "Whisper model to use (tiny, base, small, medium, large).";

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
      paste:
        method: ${builtins.toJSON cfg.paste.method}
        shortcut:
          modifiers: ${builtins.toJSON cfg.paste.shortcut.modifiers}
          key: ${builtins.toJSON cfg.paste.shortcut.key}
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
      path = [
        pkgs.procps
        pkgs.ydotool
        pkgs.wl-clipboard
        pkgs.wtype
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
