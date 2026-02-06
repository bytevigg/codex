# MVP Plan: macOS YouTube Character Companion (Days, Not Weeks)

## What you asked for
- Run in the background on **your macOS machine**.
- Watch for wake phrase: **"Hey YouTube"**.
- When triggered while a YouTube video is playing:
  1. Pause the video.
  2. Generate a kid-safe, in-character spoken response using cloud APIs.
  3. Speak for ~10 seconds and **finish the sentence naturally**.
  4. Resume YouTube playback automatically.
- Use ephemeral processing (no recordings retained).
- Include parent controls (on/off and rate limits).

## Recommended MVP scope (v0)
This keeps complexity low while proving the core loop:

1. **Audio wake phrase detector** (always-on local mic listener).
2. **YouTube pause/resume controller** for Chrome/Safari via AppleScript (target active tab if youtube.com).
3. **Screen context snapshot** (1-2 current frames) to infer character + scene.
4. **Cloud LLM response** with strict child safety policy + short output budget.
5. **TTS playback** with playful voice.
6. **Parent settings file** (YAML/JSON): enabled hours, max interactions/hour, banned topics.

## High-level architecture

```text
[Mic Listener]
   -> wake phrase event ("hey youtube")
      -> [Session Orchestrator]
          -> [YouTube Controller.pause()]
          -> [Screen Capture: latest frame]
          -> [ASR: child speech (2-3s)]
          -> [Prompt Builder + Safety Rules]
          -> [LLM (vision+text) short response]
          -> [TTS playback ~10s]
          -> [YouTube Controller.resume()]
```

## Concrete tech stack (macOS-first)
- **Language:** Python 3.11+
- **Audio input/wake phrase:** Picovoice Porcupine (wake word) or openWakeWord
- **ASR:** OpenAI realtime/transcription endpoint (cloud)
- **Vision + response:** OpenAI multimodal model (image + text)
- **TTS:** OpenAI TTS (short response)
- **Screen capture:** `mss` (frame grab)
- **YouTube control:** AppleScript via `osascript` (Chrome/Safari)
- **Background app runtime:** LaunchAgent + simple menu bar toggle later

## Safety policy for kid mode (required in every generation)
- Never discuss violence, fear themes, medical, politics, adult topics.
- If user asks unsafe content: gently redirect to playful/educational topic.
- Keep sentences short, warm, and age-appropriate.
- No commands that encourage risky behavior.
- Hard-limit reply length to ~2 sentences (target 8–12 seconds spoken).

## Parent controls (MVP)
Config file: `~/.youtube-buddy/config.json`

```json
{
  "enabled": true,
  "wake_phrase": "hey youtube",
  "max_interactions_per_hour": 8,
  "cooldown_seconds": 45,
  "active_hours": [7, 20],
  "strict_kid_safe": true,
  "blocked_topics": ["violence", "politics", "religion", "scary"]
}
```

## State machine (important for reliability)
- `IDLE` -> listening
- `TRIGGERED` -> wake phrase detected
- `PAUSED` -> YouTube paused
- `CAPTURING` -> frame + child utterance sampled
- `RESPONDING` -> LLM + TTS
- `RESUMING` -> YouTube resumed
- back to `IDLE`

Guardrails:
- If any step fails, attempt resume and return to `IDLE`.
- Max interaction window: 15s hard timeout.
- Cooldown enforcement to avoid repeated triggers.

## Delivery plan (days)

### Day 1
- Build wake phrase listener.
- Pause/resume YouTube active tab.
- Add cooldown and hourly cap.

### Day 2
- Capture frame + child speech.
- Create kid-safe prompt template.
- Generate and play TTS response.

### Day 3
- Add reliability/timeouts/recovery.
- Add config + logs (ephemeral session logs only).
- Test with Chrome and Safari.

## Acceptance criteria for MVP
- Wake phrase triggers in <1.5s.
- If YouTube is active, video pauses reliably.
- System responds in character within 3–5s.
- Spoken reply is kid-safe and <=15s.
- Playback resumes automatically after speaking.
- No audio/video files persisted by default.

## Open item before implementation
- Preferred response voice persona: playful female/male/accent. (Needed to lock TTS voice selection.)
