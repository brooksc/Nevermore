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

# Sign with a stable identity so Keychain items survive rebuilds. An ad-hoc
# signature (`-`) gets a fresh code identity every build, which invalidates the
# ACL on any Keychain item the app created — so the app can't read its own saved
# password after a rebuild. A Developer ID cert has a persistent designated
# requirement, which keeps the Keychain ACL valid across rebuilds.
#
# Identity resolution: $MAILSCRUB_SIGN_IDENTITY, else the first Developer ID
# Application cert in the keychain, else ad-hoc (with a warning).
SIGN_ID="${MAILSCRUB_SIGN_IDENTITY:-}"
if [ -z "$SIGN_ID" ]; then
  SIGN_ID=$(security find-identity -v -p codesigning \
    | awk -F'"' '/Developer ID Application/{print $2; exit}')
fi

if [ -n "$SIGN_ID" ]; then
  codesign --force --options runtime --sign "$SIGN_ID" "$APP"
  echo "signed: $SIGN_ID" >&2
else
  codesign --force --sign - "$APP" >/dev/null 2>&1 || true
  echo "WARNING: ad-hoc signed — no Developer ID cert found. The saved app" >&2
  echo "         password will not persist across rebuilds. Set" >&2
  echo "         MAILSCRUB_SIGN_IDENTITY to a signing identity to fix this." >&2
fi
echo "$APP"
