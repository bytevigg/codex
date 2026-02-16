from datetime import datetime

from youtube_buddy import orchestrator as orchestrator_module
from youtube_buddy.config import Settings
from youtube_buddy.orchestrator import SessionOrchestrator


class _FakeAI:
    def __init__(self):
        self.speak_calls = 0

    def transcribe(self, _audio_path):
        return "Bluey says hello"

    def generate_reply(self, *_args, **_kwargs):
        return "Bluey says let's keep learning and having fun!"

    def speak(self, _text):
        self.speak_calls += 1


class _FakeYouTube:
    def __init__(self, pause_success_on=2):
        self.pause_calls = 0
        self.resume_calls = 0
        self.pause_success_on = pause_success_on

    def pause(self):
        self.pause_calls += 1
        return self.pause_calls >= self.pause_success_on

    def resume(self):
        self.resume_calls += 1
        return True


class _FakeTelemetry:
    def __init__(self):
        self.events = []

    def emit(self, name, **payload):
        self.events.append((name, payload))


class _AudioPath:
    def exists(self):
        return False

    def unlink(self, missing_ok=False):
        return None


def test_handle_trigger_retries_pause_and_speaks(monkeypatch):
    settings = Settings()
    settings.retries.pause = 1
    settings.protagonist.accept_wake_only_when_ready = False

    monkeypatch.setattr(orchestrator_module, "AIClient", lambda _settings: _FakeAI())
    orchestrator = SessionOrchestrator(settings)
    orchestrator.ai = _FakeAI()
    orchestrator.youtube = _FakeYouTube(pause_success_on=2)
    orchestrator.telemetry = _FakeTelemetry()

    monkeypatch.setattr("youtube_buddy.orchestrator.capture_screen_png", lambda: b"frame")
    monkeypatch.setattr("youtube_buddy.orchestrator.record_child_speech", lambda seconds=3: _AudioPath())
    monkeypatch.setattr(
        "youtube_buddy.orchestrator.datetime",
        type("_D", (), {"now": staticmethod(lambda: datetime(2025, 1, 1, 10, 0, 0))}),
    )

    result = orchestrator.handle_trigger()
    assert "Bluey says" in result
    assert orchestrator.youtube.pause_calls == 2
    assert orchestrator.youtube.resume_calls >= 1
    assert orchestrator.ai.speak_calls == 1


def test_handle_trigger_gates_when_protagonist_not_ready(monkeypatch):
    settings = Settings()
    settings.protagonist.accept_wake_only_when_ready = True

    monkeypatch.setattr(orchestrator_module, "AIClient", lambda _settings: _FakeAI())
    orchestrator = SessionOrchestrator(settings)
    orchestrator.ai = _FakeAI()
    orchestrator.youtube = _FakeYouTube(pause_success_on=1)
    orchestrator.telemetry = _FakeTelemetry()

    monkeypatch.setattr("youtube_buddy.orchestrator.capture_screen_png", lambda: b"frame")
    monkeypatch.setattr(
        "youtube_buddy.orchestrator.datetime",
        type("_D", (), {"now": staticmethod(lambda: datetime(2025, 1, 1, 10, 0, 0))}),
    )

    result = orchestrator.handle_trigger()
    assert result == "protagonist not ready yet"
    assert orchestrator.youtube.pause_calls == 0
