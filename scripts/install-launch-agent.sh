#!/usr/bin/env bash
# Installs the LaunchAgent so AudioOutputSwitcher starts at login, and starts
# it immediately. Re-run after rebuilding to pick up a fresh binary path.
set -euo pipefail

cd "$(dirname "$0")/.."

LABEL="com.danhirst.audiooutputswitcher"
PLIST_SRC="LaunchAgent/${LABEL}.plist"
PLIST_DEST="$HOME/Library/LaunchAgents/${LABEL}.plist"
APP_BINARY="$HOME/Applications/AudioOutputSwitcher.app/Contents/MacOS/AudioOutputSwitcher"

if [ ! -x "$APP_BINARY" ]; then
    echo "error: $APP_BINARY not found. Run scripts/build.sh first." >&2
    exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents"
sed "s#__HOME__#${HOME}#g" "$PLIST_SRC" > "$PLIST_DEST"

echo "==> (Re)loading LaunchAgent ${LABEL}"
launchctl bootout "gui/$(id -u)/${LABEL}" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_DEST"
launchctl enable "gui/$(id -u)/${LABEL}"

echo "==> Installed. It will now start automatically at login, and is running now."
echo "    Logs: /tmp/audiooutputswitcher.log and /tmp/audiooutputswitcher.err"
