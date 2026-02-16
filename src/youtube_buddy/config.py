from __future__ import annotations

from pathlib import Path
from pydantic import BaseModel, Field


DEFAULT_CONFIG_PATH = Path.home() / ".youtube-buddy" / "config.json"


class Settings(BaseModel):
    class CharacterSettings(BaseModel):
        max_spoken_seconds: int = 12
        narration_person: str = "third_person"
        strict_persona: bool = True
        voice_policy: str = "style_inspired_distinct"

    class ProtagonistSettings(BaseModel):
        preload_window_seconds: int = 30
        history_window_seconds: int = 60
        open_world: bool = True
        accept_wake_only_when_ready: bool = True
        min_confidence: float = 0.45

    class ContentPolicySettings(BaseModel):
        kids_only: bool = True

    class RetrySettings(BaseModel):
        pause: int = 1
        generation: int = 1

    class TelemetrySettings(BaseModel):
        enabled: bool = True
        events: list[str] = Field(
            default_factory=lambda: [
                "wake_detected",
                "pause_success",
                "protagonist_confidence",
                "response_latency_ms",
                "resume_success",
            ]
        )

    class LauncherSettings(BaseModel):
        mode: str = "microphone"
        wake_poll_seconds: float = 1.2

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
    character: CharacterSettings = Field(default_factory=CharacterSettings)
    protagonist: ProtagonistSettings = Field(default_factory=ProtagonistSettings)
    content_policy: ContentPolicySettings = Field(default_factory=ContentPolicySettings)
    retries: RetrySettings = Field(default_factory=RetrySettings)
    telemetry: TelemetrySettings = Field(default_factory=TelemetrySettings)
    launcher: LauncherSettings = Field(default_factory=LauncherSettings)


DEFAULT_SETTINGS = Settings()


def load_settings(path: Path = DEFAULT_CONFIG_PATH) -> Settings:
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(DEFAULT_SETTINGS.model_dump_json(indent=2))
        return DEFAULT_SETTINGS

    return Settings.model_validate_json(path.read_text())
