from __future__ import annotations

import os
from datetime import datetime

from youtube_buddy.ai import AIClient
from youtube_buddy.audio import record_child_speech
from youtube_buddy.capture import capture_screen_png
from youtube_buddy.config import Settings
from youtube_buddy.rate_limit import InteractionLimiter
from youtube_buddy.state import SessionState
from youtube_buddy.youtube_control import YouTubeController


class SessionOrchestrator:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.state = SessionState.IDLE
        self.youtube = YouTubeController()
        self.ai = AIClient(settings)
        self.limiter = InteractionLimiter(
            max_per_hour=settings.max_interactions_per_hour,
            cooldown_seconds=settings.cooldown_seconds,
        )

    def handle_trigger(self) -> str:
        now = datetime.now()
        if not self._within_active_hours(now):
            return "outside active hours"
        if not self.settings.enabled:
            return "disabled by config"
        if not self.limiter.can_interact(now):
            return "rate limit/cooldown active"

        self.state = SessionState.TRIGGERED
        paused = self.youtube.pause()
        self.state = SessionState.PAUSED

        audio_path = None
        try:
            self.state = SessionState.CAPTURING
            screenshot = capture_screen_png()
            audio_path = record_child_speech(seconds=3)
            transcript = self.ai.transcribe(audio_path)

            self.state = SessionState.RESPONDING
            reply = self.ai.generate_reply(transcript, screenshot)
            self.ai.speak(reply)
            return reply
        finally:
            if audio_path and audio_path.exists():
                audio_path.unlink(missing_ok=True)
            self.state = SessionState.RESUMING
            if paused:
                self.youtube.resume()
            self.state = SessionState.IDLE
            self.limiter.record(now)

    def _within_active_hours(self, now: datetime) -> bool:
        start, end = self.settings.active_hours
        return start <= now.hour <= end


def ensure_env() -> None:
    if not os.getenv("OPENAI_API_KEY"):
        raise RuntimeError("OPENAI_API_KEY must be set")
