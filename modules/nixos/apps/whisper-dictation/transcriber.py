"""Transcription through a local whisper.cpp server."""

from __future__ import annotations

import logging
import re
import threading
import time
import uuid
from collections.abc import Callable
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

logger = logging.getLogger(__name__)


class WhisperTranscriber:
    """Sends WAV recordings to a warm, localhost-only whisper.cpp server."""

    def __init__(self, config):
        self.config = config
        self.server_url = self.config.get(
            "whisper.server_url", "http://127.0.0.1:8178/inference"
        )

    @staticmethod
    def _multipart_body(audio_file: Path, fields: dict[str, str]) -> tuple[bytes, str]:
        boundary = f"----whisper-dictation-{uuid.uuid4().hex}"
        chunks: list[bytes] = []

        for name, value in fields.items():
            chunks.extend(
                [
                    f"--{boundary}\r\n".encode(),
                    (
                        f'Content-Disposition: form-data; name="{name}"'
                        "\r\n\r\n"
                    ).encode(),
                    str(value).encode(),
                    b"\r\n",
                ]
            )

        chunks.extend(
            [
                f"--{boundary}\r\n".encode(),
                (
                    'Content-Disposition: form-data; name="file"; '
                    f'filename="{audio_file.name}"\r\n'
                ).encode(),
                b"Content-Type: audio/wav\r\n\r\n",
                audio_file.read_bytes(),
                b"\r\n",
                f"--{boundary}--\r\n".encode(),
            ]
        )

        return b"".join(chunks), boundary

    def _request(self, audio_file: Path) -> str:
        language = self.config.get("whisper.language", "auto")
        beam_size = int(self.config.get("whisper.beam_size", 5))
        initial_prompt = self.config.get("whisper.initial_prompt", "")

        fields = {
            "response_format": "text",
            "temperature": "0.0",
            "beam_size": str(beam_size),
            "best_of": str(beam_size),
        }
        if language:
            fields["language"] = language
        if initial_prompt:
            fields["prompt"] = initial_prompt

        body, boundary = self._multipart_body(audio_file, fields)
        request = Request(
            self.server_url,
            data=body,
            headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
            method="POST",
        )

        for attempt in range(5):
            try:
                with urlopen(request, timeout=120) as response:
                    return response.read().decode("utf-8")
            except HTTPError as error:
                details = error.read().decode("utf-8", errors="replace")
                raise RuntimeError(
                    f"whisper.cpp returned HTTP {error.code}: {details}"
                ) from error
            except URLError as error:
                if attempt == 4:
                    raise RuntimeError(
                        f"Cannot reach whisper.cpp at {self.server_url}: {error.reason}"
                    ) from error
                time.sleep(1)

        raise RuntimeError("whisper.cpp request failed")

    def transcribe(self, audio_file: Path) -> str | None:
        try:
            text = self._request(audio_file).strip()
            logger.info("Transcribed: %s", text[:80])
            return self._post_process(text) or None
        except Exception:
            logger.exception("Transcription error")
            raise

    def transcribe_async(
        self,
        audio_file: Path,
        on_complete: Callable[[str | None], None],
        on_error: Callable[[str], None],
    ):
        def run():
            try:
                on_complete(self.transcribe(audio_file))
            except Exception as e:
                on_error(str(e))

        threading.Thread(target=run, daemon=True).start()

    def _post_process(self, text: str) -> str:
        if not text:
            return ""
        text = text.strip()
        if self.config.get("processing.remove_filler_words", True):
            text = re.sub(r"\b(um|uh)\b", "", text, flags=re.IGNORECASE)
            text = re.sub(r"\s+", " ", text).strip()
        if self.config.get("processing.auto_capitalize", True) and text:
            text = text[0].upper() + text[1:]
        return text
