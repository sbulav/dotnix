"""Desktop-notification feedback without a GTK dependency."""

import logging
import subprocess

logger = logging.getLogger(__name__)


class DictationUI:
    """Reports dictation state through notify-send."""

    def __init__(self, config):
        self.config = config
        self.notification_icon = "audio-input-microphone"

    def _notify(self, title: str, message: str, urgency: str = "normal"):
        try:
            subprocess.Popen(
                [
                    "notify-send",
                    "-i",
                    self.notification_icon,
                    "-u",
                    urgency,
                    title,
                    message,
                    "-t",
                    "3000",
                ]
            )
        except Exception:
            logger.exception("Notification error")

    def show_ready(self):
        logger.info("UI: Ready")

    def show_recording(self):
        logger.info("UI: Recording")
        self._notify("Dictation", "Recording… release the key to stop")

    def show_transcribing(self):
        logger.info("UI: Transcribing")
        self._notify("Dictation", "Transcribing…")

    def show_success(self, text: str):
        preview = text[:50] + ("..." if len(text) > 50 else "")
        logger.info("UI: Success - %s", preview)
        self._notify("Dictation complete", preview)

    def show_error(self, message: str):
        logger.warning("UI: Error - %s", message)
        self._notify("Dictation error", message, urgency="critical")

    def close(self):
        logger.info("UI: Closing")
