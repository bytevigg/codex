You are a principal-level software engineer. Build a production-quality Python application called **YouTube Buddy** (package name: `youtube_buddy`) that runs on macOS and acts as a background kids-safe companion for YouTube videos. Deliver the entire codebase in one pass, including implementation, tests, docs, and packaging.

# 1) Product Objective (Non-Negotiable)
When a child says the wake phrase **"hey youtube"** during a YouTube video in Chrome or Safari:
1. Detect wake phrase from microphone input.
2. Pause YouTube playback in the active browser tab.
3. Capture current screen context + child utterance.
4. Identify likely protagonist (character) with confidence-gated readiness.
5. Generate a strict kid-safe, **third-person** in-character response.
6. Speak response using TTS (target <12s spoken response).
7. Resume YouTube playback automatically.

App must be macOS-first and use AppleScript (`osascript`) for browser control. Use ephemeral local audio capture files (delete after each use).

---

# 2) Hard Requirements

## Platform and runtime
- Python 3.11+
- macOS-only runtime assumptions
- Browser support: **Google Chrome** and **Safari** only
- CLI entrypoint command: `youtube-buddy`

## Functional constraints
- Wake phrase default: `hey youtube`
- Wake gating: if protagonist readiness is required and not ready, ignore trigger and return a clear status message.
- Third-person persona format is mandatory (e.g., `Bluey says ...`)
- Response length constrained to approximately 10–12 seconds spoken
- Parent controls:
  - enabled/disabled master switch
  - active hours window
  - per-hour interaction cap
  - cooldown seconds between turns
  - blocked topics list
- Retry policy:
  - pause retry count configurable
  - generation retry count configurable

## Reliability and safety
- Strict kid-safe policy; no violence, fear, medical, politics, religion, adult content.
- If generation fails after retries: return brief fallback and resume playback.
- If TTS fails: return brief speaking-failure message and resume playback.
- If pause fails after retries: return inability-to-control message.
- Always attempt resume in `finally` path.

## Data handling
- No persistent raw recordings.
- Temporary microphone WAV files must be deleted after transcription.
- Telemetry events may be persisted as JSONL.
- Protagonist correction boosts may be persisted in JSON.

---

# 3) Architecture
Implement these modules under `src/youtube_buddy/`:

1. `app.py`
   - Main runtime loop.
   - Two launch modes:
     - `microphone` mode: periodic short recording + transcription to detect wake phrase.
     - `text` mode: terminal simulation for development.

2. `orchestrator.py`
   - Owns end-to-end turn lifecycle and state transitions:
     - `IDLE -> TRIGGERED -> PAUSED -> CAPTURING -> RESPONDING -> RESUMING -> IDLE`
   - Components:
     - `YouTubeController`
     - `AIClient`
     - `TelemetryLogger`
     - `CorrectionStore`
     - `ProtagonistTracker`
     - `InteractionLimiter`
   - Methods:
     - `warm_protagonist_state()`
     - `capture_and_transcribe_wake_phrase(seconds=1.2)`
     - `_pause_with_retry()`
     - `_generate_with_retry(...)`
     - `handle_trigger()`
     - `_within_active_hours(now)`
     - `ensure_env()` validates `OPENAI_API_KEY`

3. `config.py`
   - Pydantic settings model with nested classes and defaults.
   - Default config path: `~/.youtube-buddy/config.json`
   - If config file missing: write defaults and return them.

4. `ai.py`
   - `AIClient` using OpenAI SDK.
   - Methods:
     - `transcribe(audio_path)` using `gpt-4o-mini-transcribe`
     - `generate_reply(user_text, screenshot_png, protagonist_name=None)` using multimodal responses API + image input
     - `enforce_persona_contract(text, protagonist_name)` to ensure strict third-person and spoken-length cap
     - `speak(text)` using `gpt-4o-mini-tts` and playback via `sounddevice` + `soundfile`

5. `youtube_control.py`
   - AppleScript pause/play for active YouTube tab in Chrome/Safari.
   - `get_active_video_context()` extracts URL/title/channel/description via JS in tab and returns structured context.
   - Helpers parse YouTube `video_id` and derive `series_hint` from title.

6. `capture.py`
   - Screen capture via `mss` + PIL conversion to PNG bytes.

7. `audio.py`
   - Microphone capture via `sounddevice` to temp WAV via `soundfile`.

8. `protagonist.py`
   - `ProtagonistCandidate`, `ProtagonistState` dataclasses.
   - `ProtagonistTracker` keyed by frame-derived `video_id` hash.
   - Candidate inference from transcript named entities (simple regex heuristic acceptable in v1.5 baseline).
   - Readiness true when confidence >= threshold OR preload window elapsed.
   - Correction application raises confidence and stores boost.

9. `corrections.py`
   - Persistent correction score store at `~/.youtube-buddy/protagonist_corrections.json`.
   - `detect_correction(text)` supports phrases like `that's X` and `it is X`.

10. `rate_limit.py`
    - Rolling-hour interaction limiter + cooldown enforcement.

11. `telemetry.py`
    - JSONL telemetry at `~/.youtube-buddy/telemetry_events.jsonl`.
    - Event filtering based on configured allowlist.

12. `state.py`
    - `SessionState` enum.

---

# 4) Configuration Schema and Defaults (Exact)
Create a `Settings` model with defaults:

- top-level:
  - `enabled = true`
  - `wake_phrase = "hey youtube"`
  - `max_interactions_per_hour = 8`
  - `cooldown_seconds = 45`
  - `active_hours = [7, 20]`
  - `strict_kid_safe = true`
  - `blocked_topics = ["violence", "politics", "religion", "scary"]`
  - `voice = "alloy"`

- `character`:
  - `max_spoken_seconds = 12`
  - `narration_person = "third_person"`
  - `strict_persona = true`
  - `voice_policy = "style_inspired_distinct"`

- `protagonist`:
  - `preload_window_seconds = 30`
  - `history_window_seconds = 60`
  - `open_world = true`
  - `accept_wake_only_when_ready = true`
  - `min_confidence = 0.45`

- `content_policy`:
  - `kids_only = true`

- `retries`:
  - `pause = 1`
  - `generation = 1`

- `telemetry`:
  - `enabled = true`
  - allowed events include at least:
    - `wake_detected`
    - `protagonist_confidence`
    - `protagonist_ready`
    - `pause_attempt`
    - `response_start`
    - `response_complete`
    - `resume_success`
    - `turn_outcome`
    - `response_latency_ms`
    - `latency_slo`

- `launcher`:
  - `mode = "microphone"`
  - `wake_poll_seconds = 1.2`

---

# 5) Behavioral Contracts

## Trigger handling order
1. Emit wake telemetry.
2. Reject if outside active hours.
3. Reject if disabled.
4. Reject if limiter denies (cooldown/hourly cap).
5. Update protagonist gate state from fresh screenshot.
6. If gating enabled and not ready: return `"protagonist not ready yet"`.
7. Pause YouTube with retry.
8. Capture screen + child speech.
9. Transcribe.
10. Detect correction phrase and apply.
11. Update protagonist state again with transcript.
12. Generate reply with retries.
13. Speak reply.
14. Resume playback in `finally`.
15. Record limiter and telemetry outcome.

## Return messages (human-readable)
Use stable strings for expected failures:
- `"outside active hours"`
- `"disabled by config"`
- `"rate limit/cooldown active"`
- `"protagonist not ready yet"`
- `"unable to control youtube playback"`
- `"I had trouble answering right now."`
- `"I had trouble speaking right now."`

---

# 6) AI Prompting Policy
Use a system prompt that enforces:
- kid-safe and warm tone
- blocked-topic avoidance + gentle redirection
- no violent/scary/medical/political/religious/adult content
- short natural completion
- 1–2 short sentences, ~10 seconds target

User prompt must include:
- transcribed child text
- blocked topics
- protagonist candidate name
- instruction for strict third-person response style
- current screenshot as image input

Apply post-generation persona enforcement:
- Convert first-person phrasing away from `I` when needed.
- Ensure response starts with `<protagonist> says ...` if absent.
- Truncate to max word budget derived from `max_spoken_seconds`.

---

# 7) Testing Requirements
Provide pytest suite that validates at minimum:

1. Config defaults include beyond-MVP fields:
   - launcher microphone mode
   - wake poll seconds
   - third-person settings
   - protagonist gating on
   - kids-only content policy

2. Persona enforcement:
   - first-person text becomes third-person prefixed output

3. Corrections and protagonist behavior:
   - detect correction phrases
   - readiness after preload window
   - correction boosts confidence

4. Orchestrator behavior:
   - retries pause according to retry config
   - resumes playback
   - calls speak on successful path
   - gates wake when protagonist not ready

5. Rate limiting:
   - cooldown enforcement
   - rolling hourly cap and expiry behavior

Tests should use monkeypatch/fakes, avoid requiring live OpenAI/network/browser/audio devices.

---

# 8) Packaging and Tooling
Create `pyproject.toml` with:
- package name `youtube-buddy`
- src layout
- dependencies:
  - `openai>=1.0.0`
  - `pydantic>=2`
  - `Pillow>=10`
  - `mss>=9`
- optional extra `audio`:
  - `sounddevice>=0.4`
  - `soundfile>=0.12`
- console script:
  - `youtube-buddy = youtube_buddy.app:main`
- pytest config/discovery and clean build metadata

---

# 9) Documentation Deliverables
Provide:
1. `README.md` with quick start, env vars, launch modes, macOS constraints.
2. MVP plan doc describing initial architecture and acceptance criteria.
3. v1.5 spec doc describing protagonist-awareness, wake gating, telemetry, and rollout slices.
4. install script for macOS LaunchAgent setup and environment template.

---

# 10) Implementation Notes / Decisions Already Chosen
Treat these as pre-answered product decisions:
- Voice cloning is out-of-scope; use style-inspired distinct TTS only.
- No subtitle fallback on TTS failure.
- No persona allow/block parental UI in this phase.
- Protagonist recognition is open-world, confidence-based.
- Wake phrase should only activate when protagonist state is ready if gating is enabled.
- Correction loop must update same-session behavior immediately and persist soft preference for later.

---

# 11) Quality Bar
- Keep code simple, explicit, and readable.
- Prefer boring reliable patterns over abstraction-heavy designs.
- Handle failures gracefully and return to `IDLE` state.
- Ensure temporary files are cleaned up.
- Ensure module boundaries are clear.

---

# 12) Final Output Format You Must Produce
Return:
1. Full file tree.
2. Complete code for every file.
3. Commands to create env, install dependencies, run app, run tests.
4. Example config JSON.
5. Short operational runbook (how to use in microphone mode and text mode).

You are expected to implement everything above in one shot with no TODO placeholders.
