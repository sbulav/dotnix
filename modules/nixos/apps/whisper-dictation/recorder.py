"""Audio recording through PipeWire."""

from __future__ import annotations

import logging
import os
import subprocess
from pathlib import Path

logger = logging.getLogger(__name__)


class AudioRecorder:
    """Records 16 kHz mono PCM audio with pw-record."""

    def __init__(self, config):
        self.config = config
        runtime_dir = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp"))
        self.temp_dir = runtime_dir / "whisper-dictation"
        self.temp_dir.mkdir(mode=0o700, exist_ok=True)
        self.audio_file = self.temp_dir / "recording.wav"
        self.process: subprocess.Popen | None = None

    def start(self):
        """Start recording audio."""
        if self.audio_file.exists():
            self.audio_file.unlink()

        logger.info("Starting audio recording...")
        self.process = subprocess.Popen(
            [
                "pw-record",
                "--rate=16000",
                "--channels=1",
                "--channel-map=mono",
                "--format=s16",
                str(self.audio_file),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    def stop(self) -> Path | None:
        """Stop recording and return the WAV path."""
        if not self.process:
            return None

        logger.info("Stopping audio recording...")
        try:
            self.process.terminate()
            try:
                self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                logger.warning("pw-record did not stop gracefully; killing it")
                self.process.kill()
                self.process.wait()
        finally:
            self.process = None

        if self.audio_file.exists() and self.audio_file.stat().st_size > 0:
            logger.info("Recording saved to %s", self.audio_file)
            return self.audio_file

        logger.warning("Audio file was not created or is empty")
        return None
