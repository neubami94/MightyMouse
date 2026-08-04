#!/bin/bash
# Builds the gesture helper, packages it into MightyMouse.app and ad-hoc signs it.
# Usage: ./build.sh          (build + package)
#        ./build.sh restart  (build + package + reload the LaunchAgent)
set -euo pipefail
cd "$(dirname "$0")"

APP="MightyMouse.app"
EXE="MightyMouse"
AGENT="$HOME/Library/LaunchAgents/com.neubami94.mightyMouse.plist"
# Stable self-signed identity so the Accessibility (TCC) grant survives rebuilds.
SIGN_ID="MightyMouse Signing"

echo "==> Compiling"
swiftc -O main.swift -o mightymouse -framework Cocoa

echo "==> Packaging into $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp mightymouse "$APP/Contents/MacOS/$EXE"
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing"
codesign --force --deep -s "$SIGN_ID" --keychain "$HOME/Library/Keychains/login.keychain-db" "$APP"

if [[ "${1:-}" == "restart" ]]; then
  echo "==> Reloading LaunchAgent"
  launchctl unload "$AGENT" 2>/dev/null || true
  # kill any lingering instance (numeric pid only)
  PID=$(pgrep -x "$EXE" || true)
  [[ -n "$PID" ]] && kill "$PID" 2>/dev/null || true
  launchctl load -w "$AGENT"
  echo "==> Loaded. Tail log with: tail -f mightymouse.log"
fi

echo "Done."
