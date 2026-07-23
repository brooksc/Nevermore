#!/bin/bash
# Wrap the SwiftPM MailScrubApp executable into a .app bundle so it runs as a
# proper macOS app (Dock icon, menu bar, window focus). SwiftPM only emits a
# bare Mach-O; the bundle + Info.plist is what makes SwiftUI's App lifecycle
# behave like a real app rather than a background tool.
set -euo pipefail

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
CONFIG=${1:-debug}

cd "$(dirname "$0")"
BIN_DIR=$(swift build --product MailScrubApp -c "$CONFIG" --show-bin-path)
swift build --product MailScrubApp -c "$CONFIG"

APP="$BIN_DIR/MailScrub.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MailScrubApp" "$APP/Contents/MacOS/MailScrub"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>MailScrub</string>
  <key>CFBundleDisplayName</key><string>MailScrub</string>
  <key>CFBundleIdentifier</key><string>com.brooksc.mailscrub</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>MailScrub</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so Keychain access and window focus work locally.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "$APP"
