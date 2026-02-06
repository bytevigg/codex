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

mkdir -p "$SUPPORT_DIR" "$HOME/Library/LaunchAgents" "$LOG_DIR"

cat > "$RUNNER_PATH" <<RUNNER
#!/usr/bin/env bash
set -euo pipefail
cd "$REPO_ROOT"

if [[ -f ".venv/bin/activate" ]]; then
  # shellcheck disable=SC1091
  source ".venv/bin/activate"
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
  exit 0
fi

launchctl bootout "gui/$(id -u)/${AGENT_NAME}" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
launchctl enable "gui/$(id -u)/${AGENT_NAME}"
launchctl kickstart -k "gui/$(id -u)/${AGENT_NAME}"

echo "Installed LaunchAgent: ${AGENT_NAME}"
echo "Logs: $LOG_DIR"

echo "Prompting for AppleScript automation permissions (Chrome/Safari)..."
osascript -e 'tell application "Google Chrome" to get name of front window' >/dev/null 2>&1 || true
osascript -e 'tell application "Safari" to get name of front document' >/dev/null 2>&1 || true

echo "If prompted, allow Terminal/iTerm (or your shell app) to control Chrome and Safari."
echo "For microphone access, grant your terminal app in System Settings → Privacy & Security → Microphone."
