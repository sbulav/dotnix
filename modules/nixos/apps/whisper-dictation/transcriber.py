"""Transcription via faster-whisper (CTranslate2) with GPU + Silero VAD."""

import logging
import re
import threading
from collections.abc import Callable
from pathlib import Path

from faster_whisper import WhisperModel

logger = logging.getLogger(__name__)


class WhisperTranscriber:
    """Transcribes audio using faster-whisper; model is loaded lazily and kept warm."""

    def __init__(self, config):
        self.config = config
        self._model: WhisperModel | None = None
        self._model_lock = threading.Lock()

    def _get_model(self) -> WhisperModel:
        with self._model_lock:
            if self._model is None:
                model_name = self.config.get("whisper.model", "large-v3-turbo")
                device = self.config.get("whisper.device", "cuda")
                compute_type = self.config.get("whisper.compute_type", "float16")
                cpu_threads = int(self.config.get("whisper.threads", 4))

                logger.info(
                    "Loading faster-whisper model=%s device=%s compute_type=%s",
                    model_name, device, compute_type,
                )
                self._model = WhisperModel(
                    model_name,
                    device=device,
                    compute_type=compute_type,
                    cpu_threads=cpu_threads,
                )
            return self._model

    def transcribe(self, audio_file: Path) -> str | None:
        try:
            model = self._get_model()
        except Exception as e:
            logger.error("Failed to load model: %s", e, exc_info=True)
            return None

        beam_size = int(self.config.get("whisper.beam_size", 5))
        best_of = int(self.config.get("whisper.best_of", beam_size))
        language = self.config.get("whisper.language", "en")
        if language in ("auto", "", None):
            language = None
        initial_prompt = self.config.get("whisper.initial_prompt", "") or None

        vad_filter = bool(self.config.get("whisper.vad.enable", True))
        vad_parameters = {
            "min_silence_duration_ms": int(
                self.config.get("whisper.vad.min_silence_ms", 500)
            ),
            "speech_pad_ms": int(
                self.config.get("whisper.vad.speech_pad_ms", 200)
            ),
        }

        try:
            segments, info = model.transcribe(
                str(audio_file),
                language=language,
                beam_size=beam_size,
                best_of=best_of,
                temperature=0.0,
                condition_on_previous_text=False,
                initial_prompt=initial_prompt,
                vad_filter=vad_filter,
                vad_parameters=vad_parameters,
                word_timestamps=False,
            )
            text = " ".join(seg.text.strip() for seg in segments).strip()
            logger.info(
                "Transcribed (%s p=%.2f): %s",
                info.language, info.language_probability, text[:80],
            )
            return self._post_process(text) or None
        except Exception as e:
            logger.error("Transcription error: %s", e, exc_info=True)
            return None

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
