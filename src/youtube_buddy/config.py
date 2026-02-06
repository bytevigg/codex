from __future__ import annotations

from pathlib import Path
from pydantic import BaseModel, Field


DEFAULT_CONFIG_PATH = Path.home() / ".youtube-buddy" / "config.json"


class Settings(BaseModel):
    enabled: bool = True
    wake_phrase: str = "hey youtube"
    max_interactions_per_hour: int = 8
    cooldown_seconds: int = 45
    active_hours: tuple[int, int] = (7, 20)
    strict_kid_safe: bool = True
    blocked_topics: list[str] = Field(
        default_factory=lambda: ["violence", "politics", "religion", "scary"]
    )
    voice: str = "alloy"


DEFAULT_SETTINGS = Settings()


def load_settings(path: Path = DEFAULT_CONFIG_PATH) -> Settings:
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(DEFAULT_SETTINGS.model_dump_json(indent=2))
        return DEFAULT_SETTINGS

    return Settings.model_validate_json(path.read_text())
