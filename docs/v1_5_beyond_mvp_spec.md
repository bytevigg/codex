# v1.5 Spec: Protagonist-Aware YouTube Companion (macOS)

## Assumptions confirmed from product direction
1. Runtime remains macOS-only.
2. Browser support remains Chrome and Safari only.
3. Wake trigger must be real microphone wake-word detection for "hey youtube".
4. Replies must be third-person (e.g., "Bluey says...") and <12 seconds spoken.
5. App should auto-resume playback after response.

## Product goals
When the child says "hey youtube" during a kids YouTube video, the app should:
1. Pause playback.
2. Identify the likely protagonist.
3. Answer in strict in-character style (third-person), using a style-inspired-but-distinct voice.
4. Resume playback automatically.

## Non-goals
- Voice cloning exact copyrighted voices.
- Desktop overlay subtitles fallback for failed TTS.
- Persona allow/block parental control in this phase.

## Hard requirements
- Wake-to-first-audio latency target: <2.5s median.
- Safety domain: kids-only content.
- Protagonist detection source priority:
  1) title + description + channel metadata,
  2) subtitles/transcript,
  3) visual prominence heuristics over last 60 seconds when no clear series protagonist exists.
- Confidence-gated behavior:
  - During first 30 seconds of a video, do proactive protagonist identification.
  - Wake phrase should only activate once a protagonist candidate is available.
  - If still uncertain at 30 seconds, select best candidate with confidence tag and continue.
- Open-world protagonist recognition (no strict whitelist).
- User correction loop: accept correction ("that's X") and apply it for this video/session, then store as soft preference for future ranking.

## End-to-end behavior

```text
[Mic Wake Word Listener]
  -> [Session Guard + Rate Limits]
  -> [Protagonist State Ready?]
       yes -> [Pause YouTube (retry once)]
       no  -> [Ignore wake + subtle local cue]
  -> [Question Capture + ASR]
  -> [Character Prompt Build]
  -> [LLM Answer (strict third-person, kid-safe)]
  -> [TTS (style-inspired voice)]
  -> [Resume YouTube]
```

### Failure policy
- Pause failure: retry once; if still failing, announce inability to control YouTube and stop turn.
- Generation failure: retry once; on second failure, announce brief failure and resume playback.
- TTS failure: no subtitle fallback; announce brief failure and resume playback.

## Proposed architecture changes from current MVP

### 1) Protagonist inference service
Add a dedicated service that maintains continuously refreshed candidate state per active video:
- `video_id`, `channel`, `title`, `description`
- transcript snippets and named entities
- visual recurrence score from sampled frames
- final chosen protagonist + confidence

### 2) Pre-roll identification window (first 30s)
When a new video is detected:
- start metadata/transcript analysis immediately,
- sample low-frequency frames,
- finalize initial protagonist by T+30s.

### 3) Wake phrase gating
Only accept wake event once protagonist state is `READY`.
If state is `PENDING`, keep listening but ignore invocation with subtle one-line local cue.

### 4) Prompt/voice config registry
Add per-character prompt templates and voice style mapping in config. This enables strict persona formatting while preserving style-inspired audio.

### 5) Corrections pipeline
Support explicit corrections and persist as weighted associations:
- key: `(channel_id, series_hint, character_name)`
- value: confidence boost for future ranking.

## Config additions (proposal)

```json
{
  "wake_phrase": "hey youtube",
  "character": {
    "max_spoken_seconds": 12,
    "narration_person": "third_person",
    "strict_persona": true,
    "voice_policy": "style_inspired_distinct"
  },
  "protagonist": {
    "preload_window_seconds": 30,
    "history_window_seconds": 60,
    "open_world": true,
    "accept_wake_only_when_ready": true,
    "min_confidence": 0.45
  },
  "content_policy": {
    "kids_only": true
  },
  "retries": {
    "pause": 1,
    "generation": 1
  },
  "telemetry": {
    "enabled": true,
    "events": [
      "wake_detected",
      "pause_success",
      "protagonist_confidence",
      "response_latency_ms",
      "resume_success"
    ]
  }
}
```

## Latency budget (<2.5s target)
- Wake detection and dispatch: 150-250ms
- Pause API + confirmation: 300-500ms
- ASR (short utterance) + prompt assembly: 500-700ms
- Generation + first TTS chunk: 900-1100ms
- Total to first spoken audio: 1.85-2.55s

Mitigation for p95:
- pre-connect model clients,
- incremental ASR,
- shorter response token budget,
- optimistic pause with parallel prompt prep.

## Telemetry schema (minimum)
- `wake_detected(timestamp, video_id)`
- `protagonist_ready(timestamp, confidence, source_mix)`
- `pause_attempt(result, retries)`
- `response_start(latency_ms)`
- `response_complete(duration_ms)`
- `resume_attempt(result)`
- `turn_outcome(success|failure, failure_stage)`

## Rollout plan

### Slice 1: Protagonist state only
- Build inference pipeline and confidence outputs.
- No change to spoken response persona yet.

### Slice 2: Wake gating + strict third-person persona
- Gate wake on protagonist readiness.
- Enforce strict third-person response contract.

### Slice 3: Corrections + persistent ranking boosts
- Add correction capture and reuse per channel/series.

### Slice 4: Latency optimization + telemetry dashboards
- Optimize to meet <2.5s median.
- Add reliability and latency SLO reports.

## Acceptance criteria for v1.5
- Wake phrase uses real microphone detector.
- In >90% of turns, a protagonist is available by 30s of video start.
- Reply always in third-person, under 12s spoken duration.
- Pause and resume success each >98% with one retry policy.
- Median wake-to-first-audio <2.5s.
- Corrections affect next turn within same session and persist for future ranking.
