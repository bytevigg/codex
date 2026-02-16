#!/usr/bin/env bash
set -euo pipefail

if [[ "${OSTYPE:-}" != darwin* ]]; then
  echo "This installer is for macOS only."
  exit 1
fi

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUPPORT_DIR="$HOME/Library/Application Support/YouTubeBuddy"
AGENT_NAME="com.youtubebuddy.assistant"
PLIST_PATH="$HOME/Library/LaunchAgents/${AGENT_NAME}.plist"
RUNNER_PATH="$SUPPORT_DIR/run-youtube-buddy.sh"
LOG_DIR="$HOME/Library/Logs/YouTubeBuddy"
CONFIG_PATH="$HOME/.youtube-buddy/config.json"
ENV_PATH="$HOME/.youtube-buddy/env"

mkdir -p "$SUPPORT_DIR" "$HOME/Library/LaunchAgents" "$LOG_DIR" "$(dirname "$CONFIG_PATH")"

python3 - <<'PY'
from pathlib import Path
import json

config_path = Path.home() / ".youtube-buddy" / "config.json"
config_path.parent.mkdir(parents=True, exist_ok=True)

if config_path.exists():
    data = json.loads(config_path.read_text())
else:
    data = {}

launcher = data.setdefault("launcher", {})
launcher.setdefault("mode", "microphone")
launcher.setdefault("wake_poll_seconds", 1.2)

character = data.setdefault("character", {})
character.setdefault("max_spoken_seconds", 12)
character.setdefault("narration_person", "third_person")

protagonist = data.setdefault("protagonist", {})
protagonist.setdefault("accept_wake_only_when_ready", True)
protagonist.setdefault("preload_window_seconds", 30)

content_policy = data.setdefault("content_policy", {})
content_policy.setdefault("kids_only", True)

config_path.write_text(json.dumps(data, indent=2) + "\n")
PY

if [[ ! -f "$ENV_PATH" ]]; then
  cat > "$ENV_PATH" <<ENV
# YouTube Buddy environment variables
# Required: OpenAI API key
export OPENAI_API_KEY=""
ENV
fi

cat > "$RUNNER_PATH" <<RUNNER
#!/usr/bin/env bash
set -euo pipefail
cd "$REPO_ROOT"

if [[ -f ".venv/bin/activate" ]]; then
  # shellcheck disable=SC1091
  source ".venv/bin/activate"
fi

if [[ -f "$ENV_PATH" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_PATH"
fi

exec youtube-buddy
RUNNER
chmod +x "$RUNNER_PATH"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>${AGENT_NAME}</string>
    <key>ProgramArguments</key>
    <array>
      <string>${RUNNER_PATH}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/stderr.log</string>
    <key>ProcessType</key>
    <string>Interactive</string>
  </dict>
</plist>
PLIST

if [[ "$DRY_RUN" == true ]]; then
  echo "Dry run complete. Wrote:"
  echo "- $RUNNER_PATH"
  echo "- $PLIST_PATH"
  echo "- $CONFIG_PATH (updated defaults for beyond-MVP launcher mode)"
  echo "- $ENV_PATH (if missing)"
  exit 0
fi

launchctl bootout "gui/$(id -u)/${AGENT_NAME}" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
launchctl enable "gui/$(id -u)/${AGENT_NAME}"
launchctl kickstart -k "gui/$(id -u)/${AGENT_NAME}"

echo "Installed LaunchAgent: ${AGENT_NAME}"
echo "Logs: $LOG_DIR"
echo "Config: $CONFIG_PATH"
echo "Env file: $ENV_PATH"

echo "Prompting for AppleScript automation permissions (Chrome/Safari)..."
osascript -e 'tell application "Google Chrome" to get name of front window' >/dev/null 2>&1 || true
osascript -e 'tell application "Safari" to get name of front document' >/dev/null 2>&1 || true

echo "If prompted, allow Terminal/iTerm (or your shell app) to control Chrome and Safari."
echo "For microphone access, grant your terminal app in System Settings → Privacy & Security → Microphone."
echo "Set OPENAI_API_KEY in $ENV_PATH before first launch."
