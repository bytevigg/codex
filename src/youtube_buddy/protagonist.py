from __future__ import annotations

import hashlib
import re
from collections import deque
from dataclasses import dataclass
from datetime import datetime, timedelta

from youtube_buddy.config import Settings
from youtube_buddy.corrections import CorrectionStore


_NAME_PATTERN = re.compile(r"\b([A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,2})\b")


@dataclass(slots=True)
class VideoContext:
    video_id: str
    channel_id: str
    title: str
    description: str
    series_hint: str


@dataclass(slots=True)
class ProtagonistCandidate:
    name: str
    confidence: float
    source_mix: list[str]


@dataclass(slots=True)
class ProtagonistState:
    video_id: str
    ready: bool
    candidate: ProtagonistCandidate
    started_at: datetime


class ProtagonistTracker:
    def __init__(self, settings: Settings, corrections: CorrectionStore | None = None):
        self.settings = settings
        self.corrections = corrections or CorrectionStore()
        self._state: ProtagonistState | None = None
        self._frame_history: deque[tuple[datetime, str]] = deque()

    @staticmethod
    def fallback_context_from_frame(screenshot_png: bytes) -> VideoContext:
        digest = hashlib.sha1(screenshot_png).hexdigest()
        return VideoContext(
            video_id=digest[:16],
            channel_id="unknown-channel",
            title="",
            description="",
            series_hint="unknown-series",
        )

    @staticmethod
    def _extract_names(text: str) -> list[str]:
        return [m.group(1).strip() for m in _NAME_PATTERN.finditer(text)]

    def _update_visual_history(self, screenshot_png: bytes, now: datetime) -> float:
        frame_id = hashlib.sha1(screenshot_png).hexdigest()[:8]
        self._frame_history.append((now, frame_id))
        cutoff = now - timedelta(seconds=self.settings.protagonist.history_window_seconds)
        while self._frame_history and self._frame_history[0][0] < cutoff:
            self._frame_history.popleft()

        if not self._frame_history:
            return 0.0

        ids = [f for _, f in self._frame_history]
        most_common = max(set(ids), key=ids.count)
        recurrence = ids.count(most_common) / len(ids)
        return recurrence

    def _metadata_candidate(self, context: VideoContext) -> ProtagonistCandidate | None:
        text = " ".join([context.title, context.description, context.series_hint])
        names = self._extract_names(text)
        if not names:
            return None
        chosen = max(names, key=len)
        conf = min(0.9, 0.52 + len(chosen) / 40)
        conf += self.corrections.preference_score(context.channel_id, context.series_hint, chosen)
        return ProtagonistCandidate(name=chosen, confidence=min(0.99, conf), source_mix=["metadata"])

    def _transcript_candidate(self, context: VideoContext, transcript_hint: str) -> ProtagonistCandidate | None:
        names = self._extract_names(transcript_hint)
        if not names:
            return None
        chosen = max(names, key=len)
        conf = min(0.85, 0.4 + len(chosen) / 32)
        conf += self.corrections.preference_score(context.channel_id, context.series_hint, chosen)
        return ProtagonistCandidate(name=chosen, confidence=min(0.99, conf), source_mix=["transcript"])

    def _visual_candidate(self, visual_recurrence: float) -> ProtagonistCandidate:
        confidence = min(0.4, 0.18 + visual_recurrence * 0.2)
        return ProtagonistCandidate(
            name="the on-screen character",
            confidence=confidence,
            source_mix=["visual"],
        )

    def _best_candidate(
        self,
        context: VideoContext,
        transcript_hint: str,
        visual_recurrence: float,
    ) -> ProtagonistCandidate:
        metadata = self._metadata_candidate(context)
        if metadata:
            return metadata

        transcript = self._transcript_candidate(context, transcript_hint)
        if transcript:
            return transcript

        return self._visual_candidate(visual_recurrence)

    def ensure_state(self, context: VideoContext, now: datetime) -> ProtagonistState:
        if self._state is None or self._state.video_id != context.video_id:
            self._state = ProtagonistState(
                video_id=context.video_id,
                ready=False,
                candidate=ProtagonistCandidate(
                    name="the on-screen character",
                    confidence=0.0,
                    source_mix=["visual"],
                ),
                started_at=now,
            )
        return self._state

    def update(
        self,
        context: VideoContext,
        transcript_hint: str,
        screenshot_png: bytes,
        now: datetime,
    ) -> ProtagonistState:
        state = self.ensure_state(context, now)
        recurrence = self._update_visual_history(screenshot_png, now)
        candidate = self._best_candidate(context, transcript_hint, recurrence)

        preload = self.settings.protagonist.preload_window_seconds
        age = now - state.started_at
        ready = candidate.confidence >= self.settings.protagonist.min_confidence

        if age >= timedelta(seconds=preload):
            ready = True
            if candidate.confidence < self.settings.protagonist.min_confidence:
                candidate = ProtagonistCandidate(
                    name=candidate.name,
                    confidence=max(candidate.confidence, self.settings.protagonist.min_confidence),
                    source_mix=[*candidate.source_mix, "preload_forced"],
                )

        state.ready = ready
        state.candidate = candidate
        return state

    def apply_correction(self, context: VideoContext, corrected_name: str) -> None:
        if not self._state:
            return
        self.corrections.boost_preference(context.channel_id, context.series_hint, corrected_name)
        self._state.candidate = ProtagonistCandidate(
            name=corrected_name,
            confidence=0.95,
            source_mix=["user_correction"],
        )
        self._state.ready = True

    @property
    def state(self) -> ProtagonistState | None:
        return self._state
