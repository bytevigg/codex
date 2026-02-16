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

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps(self._data, indent=2, sort_keys=True), encoding="utf-8")

    def boost(self, key: str, amount: float = 0.15) -> None:
        self._data[key] = self._data.get(key, 0.0) + amount
        self.save()

    def score(self, key: str) -> float:
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
