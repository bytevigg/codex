from __future__ import annotations

import os
import statistics
import time
from collections import deque
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
from youtube_buddy.youtube_control import ActiveVideoContext, YouTubeController


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
        self._latency_ms: deque[int] = deque(maxlen=120)

    def capture_and_transcribe_wake_phrase(self, seconds: float = 1.2) -> str:
        audio_path = None
        try:
            audio_path = record_child_speech(seconds=max(0.4, seconds))
            return self.ai.transcribe(audio_path)
        finally:
            if audio_path and audio_path.exists():
                audio_path.unlink(missing_ok=True)

    def _current_video_context(self, screenshot_png: bytes) -> ActiveVideoContext:
        context = self.youtube.get_active_video_context()
        if context is not None:
            return context
        fallback = self.protagonist.fallback_context_from_frame(screenshot_png)
        return ActiveVideoContext(
            video_id=fallback.video_id,
            channel_id=fallback.channel_id,
            title=fallback.title,
            description=fallback.description,
            series_hint=fallback.series_hint,
        )

    def _pause_with_retry(self) -> bool:
        attempts = max(1, self.settings.retries.pause + 1)
        for idx in range(attempts):
            paused = self.youtube.pause()
            self.telemetry.emit("pause_attempt", result=paused, retries=idx)
            if paused:
                return True
            time.sleep(0.05)
        return False

    def _generate_with_retry(self, transcript: str, screenshot: bytes, protagonist_name: str | None) -> str | None:
        attempts = max(1, self.settings.retries.generation + 1)
        for idx in range(attempts):
            try:
                self.telemetry.emit("response_start", attempt=idx)
                return self.ai.generate_reply(transcript, screenshot, protagonist_name=protagonist_name)
            except Exception:
                continue
        return None

    def _record_latency(self, latency_ms: int) -> tuple[float, bool]:
        self._latency_ms.append(latency_ms)
        median = statistics.median(self._latency_ms)
        slo_met = median < 2500
        self.telemetry.emit("latency_slo", median_latency_ms=median, target_ms=2500, slo_met=slo_met)
        return float(median), slo_met

    def warm_protagonist_state(self) -> None:
        now = datetime.now()
        screenshot = capture_screen_png()
        context = self._current_video_context(screenshot)
        state = self.protagonist.update(context, "", screenshot, now)
        self.telemetry.emit(
            "protagonist_confidence",
            video_id=state.video_id,
            ready=state.ready,
            confidence=state.candidate.confidence,
            source_mix=state.candidate.source_mix,
        )
        if state.ready:
            self.telemetry.emit(
                "protagonist_ready",
                video_id=state.video_id,
                confidence=state.candidate.confidence,
                source_mix=state.candidate.source_mix,
            )

    def handle_trigger(self) -> str:
        start = time.perf_counter()
        now = datetime.now()
        failure_stage = ""
        turn_success = False

        screenshot_gate = capture_screen_png()
        gate_context = self._current_video_context(screenshot_gate)
        self.telemetry.emit("wake_detected", video_id=gate_context.video_id)

        if not self._within_active_hours(now):
            failure_stage = "outside_active_hours"
            return "outside active hours"
        if not self.settings.enabled:
            failure_stage = "disabled"
            return "disabled by config"
        if not self.limiter.can_interact(now):
            failure_stage = "rate_limited"
            return "rate limit/cooldown active"

        self.state = SessionState.TRIGGERED
        gate_state = self.protagonist.update(gate_context, "", screenshot_gate, now)
        self.telemetry.emit(
            "protagonist_confidence",
            video_id=gate_state.video_id,
            ready=gate_state.ready,
            confidence=gate_state.candidate.confidence,
            source_mix=gate_state.candidate.source_mix,
        )

        if gate_state.ready:
            self.telemetry.emit(
                "protagonist_ready",
                video_id=gate_state.video_id,
                confidence=gate_state.candidate.confidence,
                source_mix=gate_state.candidate.source_mix,
            )

        if self.settings.protagonist.accept_wake_only_when_ready and not gate_state.ready:
            failure_stage = "protagonist_pending"
            return "shh—still figuring out who is on screen."

        paused = self._pause_with_retry()
        self.state = SessionState.PAUSED
        if not paused:
            failure_stage = "pause_failed"
            return "I couldn't control YouTube right now."

        audio_path = None
        try:
            self.state = SessionState.CAPTURING
            screenshot = capture_screen_png()
            context = self._current_video_context(screenshot)
            audio_path = record_child_speech(seconds=3)
            transcript = self.ai.transcribe(audio_path)

            correction = detect_correction(transcript)
            if correction:
                self.protagonist.apply_correction(context, correction)

            state = self.protagonist.update(context, transcript, screenshot, now)
            protagonist_name = state.candidate.name
            self.telemetry.emit(
                "protagonist_confidence",
                video_id=state.video_id,
                ready=state.ready,
                confidence=state.candidate.confidence,
                source_mix=state.candidate.source_mix,
            )

            self.state = SessionState.RESPONDING
            raw_reply = self._generate_with_retry(transcript, screenshot, protagonist_name)
            if raw_reply is None:
                failure_stage = "generation_failed"
                return "I had trouble answering right now."

            reply = self.ai.enforce_persona_contract(raw_reply, protagonist_name)
            first_audio_latency = int((time.perf_counter() - start) * 1000)
            self.telemetry.emit("response_latency_ms", latency_ms=first_audio_latency)

            try:
                speak_start = time.perf_counter()
                self.ai.speak(reply)
                speak_duration_ms = int((time.perf_counter() - speak_start) * 1000)
            except Exception:
                failure_stage = "tts_failed"
                return "I had trouble speaking right now."

            total_duration_ms = int((time.perf_counter() - start) * 1000)
            median_latency, slo_met = self._record_latency(first_audio_latency)
            self.telemetry.emit(
                "response_complete",
                duration_ms=total_duration_ms,
                speak_duration_ms=speak_duration_ms,
                median_latency_ms=median_latency,
                slo_met=slo_met,
            )

            turn_success = True
            return reply
        finally:
            if audio_path and audio_path.exists():
                audio_path.unlink(missing_ok=True)
            self.state = SessionState.RESUMING
            resumed = self.youtube.resume()
            self.telemetry.emit("resume_attempt", result=resumed)
            self.state = SessionState.IDLE
            self.limiter.record(now)
            self.telemetry.emit(
                "turn_outcome",
                success=turn_success,
                failure_stage=(failure_stage or None),
            )

    def _within_active_hours(self, now: datetime) -> bool:
        start, end = self.settings.active_hours
        return start <= now.hour <= end


def ensure_env() -> None:
    if not os.getenv("OPENAI_API_KEY"):
        raise RuntimeError("OPENAI_API_KEY must be set")
