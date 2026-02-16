from __future__ import annotations

import json
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from youtube_buddy.config import Settings


DEFAULT_TELEMETRY_PATH = Path.home() / ".youtube-buddy" / "telemetry_events.jsonl"


@dataclass(slots=True)
class TelemetryEvent:
    name: str
    payload: dict[str, Any]
    timestamp: str


class TelemetryLogger:
    def __init__(
        self,
        settings: Settings,
        path: Path = DEFAULT_TELEMETRY_PATH,
    ) -> None:
        self._settings = settings
        self._path = path

    def emit(self, name: str, **payload: Any) -> None:
        if not self._settings.telemetry.enabled:
            return
        if name not in self._settings.telemetry.events:
            return

        event = TelemetryEvent(
            name=name,
            payload=payload,
            timestamp=datetime.now(timezone.utc).isoformat(),
        )
        self._path.parent.mkdir(parents=True, exist_ok=True)
        with self._path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(asdict(event), ensure_ascii=False) + "\n")
