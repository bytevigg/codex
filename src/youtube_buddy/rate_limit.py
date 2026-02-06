from __future__ import annotations

from collections import deque
from datetime import datetime, timedelta


class InteractionLimiter:
    def __init__(self, max_per_hour: int, cooldown_seconds: int):
        self.max_per_hour = max_per_hour
        self.cooldown_seconds = cooldown_seconds
        self._history: deque[datetime] = deque()

    def can_interact(self, now: datetime) -> bool:
        self._trim(now)
        if self._history and (now - self._history[-1]).total_seconds() < self.cooldown_seconds:
            return False
        return len(self._history) < self.max_per_hour

    def record(self, now: datetime) -> None:
        self._trim(now)
        self._history.append(now)

    def _trim(self, now: datetime) -> None:
        cutoff = now - timedelta(hours=1)
        while self._history and self._history[0] < cutoff:
            self._history.popleft()
