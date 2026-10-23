#!/usr/bin/env bash
# Builds Pulse.app (menu bar only, no Dock icon).
# Usage: ./build.sh [--install] [--run]
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Pulse"

APP="build/Pulse.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$BIN" "$APP/Contents/MacOS/Pulse"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Pulse</string>
    <key>CFBundleDisplayName</key><string>Pulse</string>
    <key>CFBundleIdentifier</key><string>com.chris.pulse</string>
    <key>CFBundleExecutable</key><string>Pulse</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS lets it run (and "Launch at login" can register)
codesign --force --sign - "$APP"

echo "Built $APP"

if [[ " $* " == *" --install "* ]]; then
    rm -rf /Applications/Pulse.app
    cp -R "$APP" /Applications/Pulse.app
    echo "Installed to /Applications/Pulse.app"
    APP="/Applications/Pulse.app"
fi

if [[ " $* " == *" --run "* ]]; then
    open "$APP"
fi
