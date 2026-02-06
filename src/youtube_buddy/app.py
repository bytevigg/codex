from __future__ import annotations

from youtube_buddy.config import load_settings
from youtube_buddy.orchestrator import SessionOrchestrator, ensure_env


def main() -> None:
    ensure_env()
    settings = load_settings()
    orchestrator = SessionOrchestrator(settings)

    print("YouTube Buddy MVP started. Type the wake phrase and press enter to simulate detection.")
    while True:
        spoken = input("> ").strip().lower()
        if spoken in {"quit", "exit"}:
            break
        if spoken != settings.wake_phrase:
            continue

        try:
            reply = orchestrator.handle_trigger()
            print(f"Buddy: {reply}")
        except KeyboardInterrupt:
            raise
        except Exception as exc:  # broad to keep background loop alive
            print(f"error: {exc}")


if __name__ == "__main__":
    main()
