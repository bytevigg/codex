# codex

MVP implementation for a macOS background-style app that pauses YouTube on wake phrase, generates a short kid-safe in-character response, speaks it, and resumes playback.

## What's included
- Session orchestrator with explicit state machine.
- Parent controls via `~/.youtube-buddy/config.json`.
- Cooldown + max interactions/hour limiting.
- YouTube pause/resume in active Chrome or Safari tab via AppleScript.
- Screen capture + child speech capture.
- OpenAI transcription + multimodal response + TTS.
- Ephemeral behavior: temporary audio capture file is deleted after each interaction.

## Quick start
```bash
python -m venv .venv
source .venv/bin/activate
pip install -e .[audio]
export OPENAI_API_KEY=...
youtube-buddy
```

Type `hey youtube` (or your configured wake phrase) and press Enter to simulate wake phrase detection.

## macOS auto-start installer (LaunchAgent)
For a background-style setup that starts at login and primes browser automation permissions:

```bash
./scripts/install_macos_companion.sh
```

What it does:
- Installs a per-user LaunchAgent (`com.youtubebuddy.assistant`) so the app starts automatically at login.
- Enables `KeepAlive` so the process is relaunched if it exits.
- Writes logs to `~/Library/Logs/YouTubeBuddy/`.
- Triggers AppleScript permission prompts for Chrome/Safari (when possible).

Use `./scripts/install_macos_companion.sh --dry-run` to preview generated files without loading the LaunchAgent.

## Config
The app auto-creates `~/.youtube-buddy/config.json` on first run.

Plan doc: `docs/mvp_macos_youtube_character_companion.md`
