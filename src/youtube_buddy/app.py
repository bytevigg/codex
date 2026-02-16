from __future__ import annotations

import time

from youtube_buddy.config import load_settings
from youtube_buddy.orchestrator import SessionOrchestrator, ensure_env


def _run_text_mode(orchestrator: SessionOrchestrator, wake_phrase: str) -> None:
    print("YouTube Buddy started in text mode. Type the wake phrase and press enter.")
    while True:
        spoken = input("> ").strip().lower()
        if spoken in {"quit", "exit"}:
            break

        orchestrator.warm_protagonist_state()

        if spoken != wake_phrase:
            continue

        try:
            reply = orchestrator.handle_trigger()
            print(f"Buddy: {reply}")
        except KeyboardInterrupt:
            raise
        except Exception as exc:  # broad to keep background loop alive
            print(f"error: {exc}")


def _run_microphone_mode(
    orchestrator: SessionOrchestrator,
    wake_phrase: str,
    poll_seconds: float,
) -> None:
    print("YouTube Buddy started in microphone mode. Listening for wake phrase.")
    while True:
        try:
            orchestrator.warm_protagonist_state()
            transcript = orchestrator.capture_and_transcribe_wake_phrase(
                seconds=poll_seconds
            )
            if wake_phrase not in transcript.lower():
                continue
            reply = orchestrator.handle_trigger()
            print(f"Buddy: {reply}")
        except KeyboardInterrupt:
            raise
        except Exception as exc:  # broad to keep background loop alive
            print(f"error: {exc}")
            time.sleep(0.25)


def main() -> None:
    ensure_env()
    settings = load_settings()
    orchestrator = SessionOrchestrator(settings)

    mode = settings.launcher.mode.strip().lower()
    if mode == "microphone":
        _run_microphone_mode(
            orchestrator,
            settings.wake_phrase,
            settings.launcher.wake_poll_seconds,
        )
        return

    _run_text_mode(orchestrator, settings.wake_phrase)


if __name__ == "__main__":
    main()
