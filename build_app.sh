#!/bin/bash
# Builds Polish.app from the SwiftPM executable.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Polish"
BUNDLE_ID="com.jinghan.polish"

swift build -c release

DIST="dist"
APP="$DIST/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/release/Polish" "$APP/Contents/MacOS/Polish"

# App icon (shown in Dock, Launchpad, Finder).
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>Polish</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHumanReadableCopyright</key><string>© jinghan</string>
</dict>
</plist>
PLIST

# Stable ad-hoc signature so the Accessibility grant survives rebuilds.
# (No --deep: the bundled codex runtime keeps its own valid signature.)
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"

echo
echo "✅ Build complete: $PWD/$APP"
echo "   Install: ditto \"$APP\" /Applications/$APP_NAME.app   (login item requires /Applications)"
