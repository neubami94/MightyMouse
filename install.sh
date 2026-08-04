#!/bin/bash
# Installs the LaunchAgent so MightyMouse starts at login, then loads it.
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(pwd)"
LABEL="com.neubami94.mightyMouse"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$REPO/MightyMouse.app/Contents/MacOS/MightyMouse</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$REPO/mightymouse.log</string>
    <key>StandardErrorPath</key>
    <string>$REPO/mightymouse.log</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load -w "$PLIST"
echo "Installed and loaded $LABEL."
echo "Grant Accessibility to 'MightyMouse' in System Settings > Privacy & Security > Accessibility (one time)."
