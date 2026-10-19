#!/bin/bash
# Build DemoInk.app (release) into dist/ and ad-hoc sign it.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="1.0.0"
BUILD="1"
APP="dist/DemoInk.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/DemoInk"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DemoInk"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.josephtessier.DemoInk</string>
    <key>CFBundleName</key><string>DemoInk</string>
    <key>CFBundleDisplayName</key><string>DemoInk</string>
    <key>CFBundleExecutable</key><string>DemoInk</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD}</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Joseph Tessier</string>
</dict>
</plist>
PLIST

codesign --force --deep -s - "$APP"
echo "OK -> $APP"
