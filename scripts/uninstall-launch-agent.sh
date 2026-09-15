#!/usr/bin/env bash
set -euo pipefail

LABEL="com.danhirst.audiooutputswitcher"

launchctl bootout "gui/$(id -u)/${LABEL}" >/dev/null 2>&1 || true
rm -f "$HOME/Library/LaunchAgents/${LABEL}.plist"

echo "==> LaunchAgent removed. The app will no longer start at login."
echo "    (Quit it from the menu bar, or 'killall AudioOutputSwitcher', if it's still running.)"
