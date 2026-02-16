from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass
from datetime import datetime, timedelta

from youtube_buddy.config import Settings
from youtube_buddy.corrections import CorrectionStore


_NAME_PATTERN = re.compile(r"\b([A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,2})\b")


@dataclass(slots=True)
class ProtagonistCandidate:
    name: str
    confidence: float
    source_mix: list[str]


@dataclass(slots=True)
class ProtagonistState:
    video_id: str
    ready: bool
    candidate: ProtagonistCandidate | None
    started_at: datetime


class ProtagonistTracker:
    def __init__(self, settings: Settings, corrections: CorrectionStore | None = None):
        self.settings = settings
        self.corrections = corrections or CorrectionStore()
        self._state: ProtagonistState | None = None

    def _video_id_from_frame(self, screenshot_png: bytes) -> str:
        return hashlib.sha1(screenshot_png).hexdigest()[:16]

    def ensure_state(self, screenshot_png: bytes, now: datetime) -> ProtagonistState:
        video_id = self._video_id_from_frame(screenshot_png)
        if self._state is None or self._state.video_id != video_id:
            self._state = ProtagonistState(
                video_id=video_id,
                ready=False,
                candidate=None,
                started_at=now,
            )
        return self._state

    def update(self, screenshot_png: bytes, transcript_hint: str, now: datetime) -> ProtagonistState:
        state = self.ensure_state(screenshot_png, now)
        candidate = self._infer_candidate(state.video_id, transcript_hint)
        preload = self.settings.protagonist.preload_window_seconds
        age = now - state.started_at
        ready = candidate is not None and (
            candidate.confidence >= self.settings.protagonist.min_confidence
            or age >= timedelta(seconds=preload)
        )
        state.ready = ready
        state.candidate = candidate
        return state

    def apply_correction(self, corrected_name: str) -> None:
        if not self._state:
            return
        key = self._correction_key(self._state.video_id, corrected_name)
        self.corrections.boost(key)
        self._state.candidate = ProtagonistCandidate(
            name=corrected_name,
            confidence=0.95,
            source_mix=["user_correction"],
        )
        self._state.ready = True

    def _correction_key(self, video_id: str, name: str) -> str:
        return f"{video_id}:{name.lower()}"

    def _infer_candidate(self, video_id: str, transcript_hint: str) -> ProtagonistCandidate | None:
        names = [m.group(1) for m in _NAME_PATTERN.finditer(transcript_hint)]
        if not names:
            return None
        winner = max(names, key=len)
        key = self._correction_key(video_id, winner)
        base_confidence = min(0.8, 0.35 + len(winner) / 24)
        confidence = min(0.99, base_confidence + self.corrections.score(key))
        return ProtagonistCandidate(
            name=winner,
            confidence=confidence,
            source_mix=["transcript"],
        )

    @property
    def state(self) -> ProtagonistState | None:
        return self._state
