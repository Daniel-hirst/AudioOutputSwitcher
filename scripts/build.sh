#!/usr/bin/env bash
# Builds the release binary and packages it into a minimal .app bundle in
# ~/Applications, then ad-hoc code-signs it so Gatekeeper lets it run locally.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="AudioOutputSwitcher"
APP_DIR="$HOME/Applications/${APP_NAME}.app"

echo "==> Building release binary"
swift build -c release

echo "==> Packaging ${APP_DIR}"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp ".build/release/${APP_NAME}" "$APP_DIR/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

echo "==> Ad-hoc code-signing"
codesign --force --deep --sign - "$APP_DIR"

echo "==> Done: $APP_DIR"
echo "    Run it directly with: open \"$APP_DIR\""
echo "    Or install the LaunchAgent with: scripts/install-launch-agent.sh"
