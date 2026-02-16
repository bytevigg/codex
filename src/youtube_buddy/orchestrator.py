from __future__ import annotations

import os
import time
from datetime import datetime

from youtube_buddy.ai import AIClient
from youtube_buddy.audio import record_child_speech
from youtube_buddy.capture import capture_screen_png
from youtube_buddy.config import Settings
from youtube_buddy.corrections import CorrectionStore, detect_correction
from youtube_buddy.protagonist import ProtagonistTracker
from youtube_buddy.rate_limit import InteractionLimiter
from youtube_buddy.state import SessionState
from youtube_buddy.telemetry import TelemetryLogger
from youtube_buddy.youtube_control import YouTubeController


class SessionOrchestrator:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.state = SessionState.IDLE
        self.youtube = YouTubeController()
        self.ai = AIClient(settings)
        self.telemetry = TelemetryLogger(settings)
        self.corrections = CorrectionStore()
        self.protagonist = ProtagonistTracker(settings, corrections=self.corrections)
        self.limiter = InteractionLimiter(
            max_per_hour=settings.max_interactions_per_hour,
            cooldown_seconds=settings.cooldown_seconds,
        )

    def capture_and_transcribe_wake_phrase(self, seconds: float = 1.2) -> str:
        audio_path = None
        try:
            audio_path = record_child_speech(seconds=max(0.4, seconds))
            return self.ai.transcribe(audio_path)
        finally:
            if audio_path and audio_path.exists():
                audio_path.unlink(missing_ok=True)

    def _pause_with_retry(self) -> bool:
        attempts = max(1, self.settings.retries.pause + 1)
        for idx in range(attempts):
            paused = self.youtube.pause()
            self.telemetry.emit("pause_success", result=paused, retries=idx)
            if paused:
                return True
            time.sleep(0.05)
        return False

    def _generate_with_retry(self, transcript: str, screenshot: bytes, protagonist_name: str | None) -> str | None:
        attempts = max(1, self.settings.retries.generation + 1)
        for _ in range(attempts):
            try:
                return self.ai.generate_reply(transcript, screenshot, protagonist_name=protagonist_name)
            except Exception:
                continue
        return None

    def warm_protagonist_state(self) -> None:
        now = datetime.now()
        screenshot = capture_screen_png()
        state = self.protagonist.update(screenshot, "", now)
        candidate = state.candidate
        self.telemetry.emit(
            "protagonist_confidence",
            video_id=state.video_id,
            ready=state.ready,
            confidence=(candidate.confidence if candidate else 0.0),
            source_mix=(candidate.source_mix if candidate else []),
        )

    def handle_trigger(self) -> str:
        start = time.perf_counter()
        now = datetime.now()
        self.telemetry.emit("wake_detected", video_id="unknown")

        if not self._within_active_hours(now):
            return "outside active hours"
        if not self.settings.enabled:
            return "disabled by config"
        if not self.limiter.can_interact(now):
            return "rate limit/cooldown active"

        self.state = SessionState.TRIGGERED

        screenshot_for_gate = capture_screen_png()
        gate_state = self.protagonist.update(screenshot_for_gate, "", now)
        candidate = gate_state.candidate
        self.telemetry.emit(
            "protagonist_confidence",
            video_id=gate_state.video_id,
            ready=gate_state.ready,
            confidence=(candidate.confidence if candidate else 0.0),
            source_mix=(candidate.source_mix if candidate else []),
        )

        if self.settings.protagonist.accept_wake_only_when_ready and not gate_state.ready:
            return "protagonist not ready yet"

        paused = self._pause_with_retry()
        self.state = SessionState.PAUSED
        if not paused:
            return "unable to control youtube playback"

        audio_path = None
        try:
            self.state = SessionState.CAPTURING
            screenshot = capture_screen_png()
            audio_path = record_child_speech(seconds=3)
            transcript = self.ai.transcribe(audio_path)

            correction = detect_correction(transcript)
            if correction:
                self.protagonist.apply_correction(correction)
                self.telemetry.emit("protagonist_confidence", corrected_to=correction, confidence=0.95, source_mix=["user_correction"])

            state = self.protagonist.update(screenshot, transcript, now)
            protagonist_name = state.candidate.name if state.candidate else None
            self.telemetry.emit(
                "protagonist_confidence",
                video_id=state.video_id,
                ready=state.ready,
                confidence=(state.candidate.confidence if state.candidate else 0.0),
                source_mix=(state.candidate.source_mix if state.candidate else []),
            )

            self.state = SessionState.RESPONDING
            reply = self._generate_with_retry(transcript, screenshot, protagonist_name)
            if reply is None:
                return "I had trouble answering right now."
            self.telemetry.emit("response_latency_ms", latency_ms=int((time.perf_counter() - start) * 1000))

            try:
                self.ai.speak(reply)
            except Exception:
                return "I had trouble speaking right now."

            self.telemetry.emit("resume_success", result=True)
            return reply
        finally:
            if audio_path and audio_path.exists():
                audio_path.unlink(missing_ok=True)
            self.state = SessionState.RESUMING
            self.youtube.resume()
            self.state = SessionState.IDLE
            self.limiter.record(now)

    def _within_active_hours(self, now: datetime) -> bool:
        start, end = self.settings.active_hours
        return start <= now.hour <= end


def ensure_env() -> None:
    if not os.getenv("OPENAI_API_KEY"):
        raise RuntimeError("OPENAI_API_KEY must be set")
