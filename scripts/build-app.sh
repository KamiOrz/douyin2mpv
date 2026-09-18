#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-icon.sh
swift build
BIN_DIR="$(swift build --show-bin-path)"
APP="$(pwd)/dist/Douyin2MPV.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp resources/live-reconnect.lua assets/AppIcon.icns assets/AppIcon.png "$APP/Contents/Resources/"
cp "$BIN_DIR/Douyin2MPV" "$APP/Contents/MacOS/Douyin2MPV"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Douyin2MPV</string>
<key>CFBundleIdentifier</key><string>local.douyin2mpv.app</string>
<key>CFBundleName</key><string>Douyin2MPV</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built: $APP"
