# YouTube Buddy — iOS

Kid-safe YouTube companion app for iOS. Listens for "hey youtube", pauses the video, captures a child's question, generates an in-character third-person response, speaks it via TTS, and resumes playback.

## Requirements

- Xcode 15+
- iOS 17.0+
- OpenAI API key

## Setup

### 1. Open in Xcode

You can either:

**Option A — XcodeGen (recommended):**
```bash
brew install xcodegen
cd YouTubeBuddy
xcodegen generate
open YouTubeBuddy.xcodeproj
```

**Option B — Manual Xcode project:**
1. Open Xcode → File → New → Project → iOS App (SwiftUI).
2. Delete the auto-generated files.
3. Drag all folders (`YouTubeBuddyApp/`, `Models/`, `Services/`, `Orchestrator/`, `Views/`, `Resources/`) into the project.
4. Set deployment target to iOS 17.0.
5. Copy `Info.plist` entries into your target's Info tab.

### 2. Set your API key

Open `Services/AIClient.swift` and replace the placeholder:

```swift
private static let apiKey = "YOUR_OPENAI_API_KEY_HERE"
```

> **Prototype only.** Before shipping, move this to Keychain or a backend proxy.

### 3. Build & Run

Select a physical device (microphone required) and hit Run.

## How it works

1. **Wake detection**: `SFSpeechRecognizer` continuously listens on-device for "hey youtube".
2. **Pause**: JavaScript bridge calls `video.pause()` on the embedded YouTube WKWebView.
3. **Capture**: Records 3 seconds of the child's question via `AVAudioRecorder`.
4. **Transcribe**: Sends WAV to OpenAI Whisper API.
5. **Protagonist detection**: Regex-based name extraction from video title/channel + transcript.
6. **Generate**: OpenAI GPT-4o-mini with kid-safe system prompt, strict third-person.
7. **Persona enforcement**: Ensures response starts with "{Character} says ...", truncates to word budget.
8. **Speak**: OpenAI TTS → AAC → `AVAudioPlayer`.
9. **Resume**: JavaScript bridge calls `video.play()`.

## Architecture

```
YouTubeBuddyApp.swift          App entry point
├── Models/
│   ├── Settings.swift          Config (Codable, @Observable)
│   ├── SessionState.swift      State machine enum
│   ├── Protagonist.swift       Candidate, State, Tracker
│   ├── VideoMetadata.swift     YouTube video context
│   └── RateLimiter.swift       Cooldown + hourly cap
├── Services/
│   ├── YouTubePlayerBridge.swift   WKWebView ↔ JS bridge
│   ├── WakeWordListener.swift      SFSpeechRecognizer
│   ├── AIClient.swift              OpenAI API (generate, TTS, transcribe)
│   ├── AudioServices.swift         AVAudioRecorder + AVAudioPlayer
│   ├── CorrectionStore.swift       Persistent protagonist corrections
│   └── TelemetryLogger.swift       JSONL event log
├── Orchestrator/
│   └── SessionOrchestrator.swift   Turn lifecycle state machine
└── Views/
    ├── PlayerView.swift            Main UI: YouTube + status + reply bubble
    ├── SettingsView.swift          Parent controls
    └── YouTubeWebView.swift        UIViewRepresentable WKWebView wrapper
```

## State machine

```
IDLE → TRIGGERED → PAUSED → CAPTURING → RESPONDING → RESUMING → IDLE
```

On any failure, the orchestrator attempts to resume playback and returns to IDLE.

## Parent controls

Accessible via the gear icon. Configurable:
- Enable/disable, wake phrase
- Active hours window
- Max interactions per hour, cooldown
- Character settings (spoken seconds, persona)
- Protagonist detection (confidence threshold, preload window)
- Blocked topics, kid-safe mode
- TTS voice selection
- Retry counts

Settings persist to `Documents/settings.json`.

## Permissions required

| Permission | Reason |
|---|---|
| Microphone | Wake phrase detection + question capture |
| Speech Recognition | On-device wake phrase processing |

## Differences from macOS version

| macOS | iOS |
|---|---|
| AppleScript browser control | WKWebView + JS bridge |
| `mss` screen capture | Video metadata from JS API |
| WAV file + OpenAI transcribe for wake | SFSpeechRecognizer (on-device) |
| `sounddevice` / `soundfile` | AVAudioRecorder / AVAudioPlayer |
| CLI + LaunchAgent | SwiftUI app |
| `~/.youtube-buddy/config.json` | Documents/settings.json + Settings UI |
| Python / Pydantic | Swift / Codable / @Observable |

## Limitations (prototype)

- API key is hardcoded (move to Keychain or proxy for production).
- No offline fallback — requires network for generation and TTS.
- YouTube mobile web may occasionally show "open in app" prompts.
- SFSpeechRecognizer has a ~60s recognition timeout; the listener auto-restarts.
- No screenshot sent to the LLM on iOS (metadata-only context).
