from datetime import datetime, timedelta

from youtube_buddy.config import Settings
from youtube_buddy.corrections import CorrectionStore, detect_correction
from youtube_buddy.protagonist import ProtagonistTracker, VideoContext


def _context() -> VideoContext:
    return VideoContext(
        video_id="vid-1",
        channel_id="channel-abc",
        title="Bluey Episode 1",
        description="Bluey and Bingo play in the park",
        series_hint="Bluey",
    )


def test_detect_correction_phrase() -> None:
    assert detect_correction("that's Bluey") == "Bluey"
    assert detect_correction("it is Bingo") == "Bingo"
    assert detect_correction("hello there") is None


def test_source_priority_prefers_metadata_over_transcript(tmp_path) -> None:
    settings = Settings()
    tracker = ProtagonistTracker(settings, corrections=CorrectionStore(tmp_path / "corrections.json"))
    now = datetime(2025, 1, 1, 10, 0, 0)

    state = tracker.update(_context(), "Somebody said Bingo", b"frame", now)
    assert state.candidate.source_mix == ["metadata"]
    assert state.candidate.name == "Bluey Episode"


def test_protagonist_ready_after_preload_even_when_uncertain(tmp_path) -> None:
    settings = Settings()
    tracker = ProtagonistTracker(settings, corrections=CorrectionStore(tmp_path / "corrections.json"))

    context = VideoContext(
        video_id="vid-2",
        channel_id="channel-xyz",
        title="",
        description="",
        series_hint="",
    )
    now = datetime(2025, 1, 1, 10, 0, 0)

    initial = tracker.update(context, "", b"frame-a", now)
    assert not initial.ready

    later = now + timedelta(seconds=settings.protagonist.preload_window_seconds + 1)
    forced = tracker.update(context, "", b"frame-b", later)
    assert forced.ready
    assert "preload_forced" in forced.candidate.source_mix


def test_correction_key_schema_and_boost(tmp_path) -> None:
    settings = Settings()
    store = CorrectionStore(tmp_path / "corrections.json")
    tracker = ProtagonistTracker(settings, corrections=store)
    now = datetime(2025, 1, 1, 10, 0, 0)

    ctx = _context()
    tracker.update(ctx, "", b"frame-a", now)
    tracker.apply_correction(ctx, "Bluey")

    assert store.preference_score(ctx.channel_id, ctx.series_hint, "Bluey") > 0
