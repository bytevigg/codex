from pathlib import Path

from youtube_buddy.config import load_settings


def test_load_settings_has_beyond_mvp_defaults(tmp_path: Path) -> None:
    config_path = tmp_path / "config.json"
    settings = load_settings(config_path)

    assert settings.launcher.mode == "microphone"
    assert settings.launcher.wake_poll_seconds == 1.2
    assert settings.character.max_spoken_seconds == 12
    assert settings.character.narration_person == "third_person"
    assert settings.protagonist.accept_wake_only_when_ready is True
    assert settings.content_policy.kids_only is True
