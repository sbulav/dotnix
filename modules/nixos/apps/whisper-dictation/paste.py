"""Text pasting module using ydotool / wtype"""

import logging
import subprocess
import time

from evdev import ecodes

logger = logging.getLogger(__name__)


class TextPaster:
    """Pastes text into active window using ydotool"""

    def __init__(self, config):
        self.config = config
        self._check_ydotool()
        self._paste_method = self.config.get("paste.method", "type")
        self._paste_modifiers = self.config.get("paste.shortcut.modifiers", ["shift"])
        self._paste_key = self.config.get("paste.shortcut.key", "insert")

        self._modifier_map = {
            "super": ecodes.KEY_LEFTMETA,
            "ctrl": ecodes.KEY_LEFTCTRL,
            "alt": ecodes.KEY_LEFTALT,
            "shift": ecodes.KEY_LEFTSHIFT,
        }

        self._key_map = {
            "insert": ecodes.KEY_INSERT,
            "v": ecodes.KEY_V,
        }

    def _check_ydotool(self):
        """Check if ydotool daemon is running"""
        try:
            result = subprocess.run(["pgrep", "-x", "ydotoold"], capture_output=True)
            if result.returncode != 0:
                logger.warning(
                    "ydotool daemon not running. Start with: systemctl --user start ydotool"
                )
        except Exception as e:
            logger.error(f"Error checking ydotool: {e}")

    def paste(self, text: str):
        """Paste text into active window"""
        if not text:
            return

        logger.info(f"Pasting text: {text[:50]}...")

        try:
            time.sleep(self.config.get("typing.start_delay", 0.3))

            if self._paste_method == "clipboard":
                subprocess.run(["wl-copy"], input=text, text=True, check=True)

                modifiers = [
                    self._modifier_map[m]
                    for m in self._paste_modifiers
                    if m in self._modifier_map
                ]
                keycode = self._key_map.get(self._paste_key)

                if keycode is None:
                    raise ValueError(f"Unsupported paste key: {self._paste_key}")

                key_events = []
                for code in modifiers:
                    key_events.append(f"{code}:1")

                key_events.append(f"{keycode}:1")
                key_events.append(f"{keycode}:0")

                for code in reversed(modifiers):
                    key_events.append(f"{code}:0")

                subprocess.run(["ydotool", "key", *key_events], check=True)
            else:
                subprocess.run(["wtype", text], check=True)

            logger.info("Text pasted successfully")

        except subprocess.CalledProcessError as e:
            logger.error(f"ydotool failed: {e}")
            raise
        except Exception as e:
            logger.error(f"Error pasting text: {e}")
            raise
