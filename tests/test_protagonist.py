from datetime import datetime, timedelta

from youtube_buddy.config import Settings
from youtube_buddy.corrections import CorrectionStore, detect_correction
from youtube_buddy.protagonist import ProtagonistTracker


def test_detect_correction_phrase() -> None:
    assert detect_correction("that's Bluey") == "Bluey"
    assert detect_correction("it is Bingo") == "Bingo"
    assert detect_correction("hello there") is None


def test_protagonist_ready_after_preload_window(tmp_path) -> None:
    settings = Settings()
    store = CorrectionStore(tmp_path / "corrections.json")
    tracker = ProtagonistTracker(settings, corrections=store)

    now = datetime(2025, 1, 1, 10, 0, 0)
    frame = b"frame-a"

    state = tracker.update(frame, "", now)
    assert not state.ready
    assert state.candidate is None

    later = now + timedelta(seconds=settings.protagonist.preload_window_seconds + 1)
    state = tracker.update(frame, "Bluey and Bingo are playing", later)
    assert state.ready
    assert state.candidate is not None
    assert state.candidate.name in {"Bluey", "Bingo"}


def test_correction_increases_confidence(tmp_path) -> None:
    settings = Settings()
    store = CorrectionStore(tmp_path / "corrections.json")
    tracker = ProtagonistTracker(settings, corrections=store)

    now = datetime(2025, 1, 1, 10, 0, 0)
    frame = b"frame-a"
    state = tracker.update(frame, "Bluey", now)
    assert state.candidate is not None
    base = state.candidate.confidence

    tracker.apply_correction("Bluey")
    boosted = tracker.update(frame, "Bluey", now + timedelta(seconds=1))
    assert boosted.candidate is not None
    assert boosted.candidate.confidence > base
