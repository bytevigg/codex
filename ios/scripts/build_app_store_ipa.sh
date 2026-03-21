#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$ROOT_DIR"
PROJECT_NAME="YouTubeBuddy"
SCHEME="YouTubeBuddy"
CONFIGURATION="Release"
ARCHIVE_PATH="$PROJECT_DIR/build/${PROJECT_NAME}.xcarchive"
EXPORT_DIR="$PROJECT_DIR/build/app-store"
EXPORT_OPTIONS_PLIST="$PROJECT_DIR/build/ExportOptions-AppStore.plist"
XCODEPROJ_PATH="$PROJECT_DIR/${PROJECT_NAME}.xcodeproj"

TEAM_ID="${APPLE_TEAM_ID:-}"
BUNDLE_ID="${PRODUCT_BUNDLE_IDENTIFIER:-com.youtubebuddy.app}"

usage() {
  cat <<EOF
Build an App Store-ready IPA for the iOS app.

Usage:
  APPLE_TEAM_ID=YOURTEAMID ./ios/scripts/build_app_store_ipa.sh

Optional environment variables:
  APPLE_TEAM_ID              Apple Developer Team ID (required)
  PRODUCT_BUNDLE_IDENTIFIER  Bundle identifier override

Requirements:
  - macOS with Xcode 15+
  - xcodebuild
  - xcodegen
  - Valid Apple Developer signing setup for the provided team
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild is required. Run this script on macOS with Xcode installed." >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is required. Install it with 'brew install xcodegen'." >&2
  exit 1
fi

if [[ -z "$TEAM_ID" ]]; then
  echo "error: APPLE_TEAM_ID is required for App Store export." >&2
  usage >&2
  exit 1
fi

mkdir -p "$PROJECT_DIR/build"

cat >"$EXPORT_OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>destination</key>
    <string>export</string>
    <key>method</key>
    <string>app-store</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
EOF

cd "$PROJECT_DIR"

echo "==> Generating Xcode project"
xcodegen generate --spec project.yml

echo "==> Archiving app"
xcodebuild \
  -project "$XCODEPROJ_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  clean archive

echo "==> Exporting IPA"
rm -rf "$EXPORT_DIR"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

echo
echo "Done. Exported files:"
find "$EXPORT_DIR" -maxdepth 1 -type f | sed 's#^# - #'
