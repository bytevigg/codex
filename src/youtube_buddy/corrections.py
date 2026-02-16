from __future__ import annotations

import json
import re
from pathlib import Path


DEFAULT_CORRECTIONS_PATH = Path.home() / ".youtube-buddy" / "protagonist_corrections.json"
_CORRECTION_PATTERNS = (
    re.compile(r"\bthat(?:'s| is)\s+([a-zA-Z][\w\- ]{1,40})", re.IGNORECASE),
    re.compile(r"\bit(?:'s| is)\s+([a-zA-Z][\w\- ]{1,40})", re.IGNORECASE),
)


class CorrectionStore:
    def __init__(self, path: Path = DEFAULT_CORRECTIONS_PATH):
        self.path = path
        self._data = self._load()

    def _load(self) -> dict[str, float]:
        if not self.path.exists():
            return {}
        try:
            raw = json.loads(self.path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            return {}
        if not isinstance(raw, dict):
            return {}

        out: dict[str, float] = {}
        for key, value in raw.items():
            if isinstance(key, str) and isinstance(value, (int, float)):
                out[key] = float(value)
        return out

    @staticmethod
    def preference_key(channel_id: str, series_hint: str, character_name: str) -> str:
        channel = (channel_id or "unknown-channel").strip().lower()
        series = (series_hint or "unknown-series").strip().lower()
        character = (character_name or "unknown-character").strip().lower()
        return f"{channel}::{series}::{character}"

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps(self._data, indent=2, sort_keys=True), encoding="utf-8")

    def boost_preference(
        self,
        channel_id: str,
        series_hint: str,
        character_name: str,
        amount: float = 0.15,
    ) -> None:
        key = self.preference_key(channel_id, series_hint, character_name)
        self._data[key] = self._data.get(key, 0.0) + amount
        self.save()

    def preference_score(self, channel_id: str, series_hint: str, character_name: str) -> float:
        key = self.preference_key(channel_id, series_hint, character_name)
        return self._data.get(key, 0.0)


def detect_correction(text: str) -> str | None:
    normalized = text.strip()
    if not normalized:
        return None

    for pattern in _CORRECTION_PATTERNS:
        match = pattern.search(normalized)
        if match:
            return " ".join(match.group(1).split()).strip(" .,!?")
    return None
