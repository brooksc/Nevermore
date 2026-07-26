#!/bin/bash
# Wrap the SwiftPM NevermoreApp executable into a .app bundle so it runs as a
# proper macOS app (Dock icon, menu bar, window focus). SwiftPM only emits a
# bare Mach-O; the bundle + Info.plist is what makes SwiftUI's App lifecycle
# behave like a real app rather than a background tool.
set -euo pipefail

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
CONFIG=${1:-debug}

cd "$(dirname "$0")"
BIN_DIR=$(swift build --product NevermoreApp -c "$CONFIG" --show-bin-path)
swift build --product NevermoreApp -c "$CONFIG"

# Version comes from the VERSION file, and the build number from the commit
# count — monotonic, reproducible from any checkout, nothing to maintain by
# hand. NEVERMORE_BUILD overrides it for a hotfix branched off an older tag,
# where the count would otherwise go backwards. See RELEASE.md.
MARKETING_VERSION=$(tr -d ' \t\n\r' < "$(dirname "$0")/VERSION")
if [ -z "$MARKETING_VERSION" ]; then
  echo "VERSION file is empty" >&2
  exit 1
fi
BUILD_NUMBER=${NEVERMORE_BUILD:-$(git -C "$(dirname "$0")" rev-list --count HEAD 2>/dev/null || echo 1)}

APP="$BIN_DIR/Nevermore.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/NevermoreApp" "$APP/Contents/MacOS/Nevermore"
cp "$(dirname "$0")/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Nevermore</string>
  <key>CFBundleDisplayName</key><string>Nevermore</string>
  <key>CFBundleIdentifier</key><string>com.brooksc.nevermore</string>
  <key>CFBundleVersion</key><string>__BUILD_NUMBER__</string>
  <key>CFBundleShortVersionString</key><string>__MARKETING_VERSION__</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>Nevermore</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <!-- Unsubscribe requests (and the manual browser sheet) hit arbitrary,
       user-directed third-party endpoints, some of which publish http-only
       List-Unsubscribe URLs. App Transport Security blocks those by default,
       so allow arbitrary loads. Justified: the destinations are chosen by the
       mail sender, not the app, and the tool's whole job is to reach them. -->
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoads</key><true/>
  </dict>
</dict>
</plist>
PLIST

# Substituted after the heredoc so the plist body stays a quoted heredoc and
# can't interpolate anything else.
/usr/bin/sed -i '' \
  -e "s/__MARKETING_VERSION__/$MARKETING_VERSION/" \
  -e "s/__BUILD_NUMBER__/$BUILD_NUMBER/" \
  "$APP/Contents/Info.plist"
echo "version: $MARKETING_VERSION ($BUILD_NUMBER)" >&2

# Sign with a stable identity so Keychain items survive rebuilds. An ad-hoc
# signature (`-`) gets a fresh code identity every build, which invalidates the
# ACL on any Keychain item the app created — so the app can't read its own saved
# password after a rebuild. A Developer ID cert has a persistent designated
# requirement, which keeps the Keychain ACL valid across rebuilds.
#
# Identity resolution: $NEVERMORE_SIGN_IDENTITY, else the first Developer ID
# Application cert in the keychain, else ad-hoc (with a warning).
SIGN_ID="${NEVERMORE_SIGN_IDENTITY:-}"
if [ -z "$SIGN_ID" ]; then
  SIGN_ID=$(security find-identity -v -p codesigning \
    | awk -F'"' '/Developer ID Application/{print $2; exit}')
fi

# App Sandbox is required for the Mac App Store but relocates the app's
# Application Support directory into a per-app container — so a sandboxed build
# won't see a database created by a non-sandboxed dev build (and vice versa).
# Keep it opt-in for local development: set NEVERMORE_SANDBOX=1 for MAS-style
# builds. (Full MAS submission additionally needs Apple Distribution signing and
# a provisioning profile — see MAS-RELEASE.md.)
ENTITLEMENTS_ARGS=()
if [ "${NEVERMORE_SANDBOX:-0}" = "1" ]; then
  ENTITLEMENTS_ARGS=(--entitlements "$(dirname "$0")/Resources/Nevermore.entitlements")
  echo "sandbox: enabled (App Support lives in the app container)" >&2
fi

if [ -n "$SIGN_ID" ]; then
  codesign --force --options runtime ${ENTITLEMENTS_ARGS[@]+"${ENTITLEMENTS_ARGS[@]}"} --sign "$SIGN_ID" "$APP"
  echo "signed: $SIGN_ID" >&2
else
  codesign --force ${ENTITLEMENTS_ARGS[@]+"${ENTITLEMENTS_ARGS[@]}"} --sign - "$APP" >/dev/null 2>&1 || true
  echo "WARNING: ad-hoc signed — no Developer ID cert found. The saved app" >&2
  echo "         password will not persist across rebuilds. Set" >&2
  echo "         NEVERMORE_SIGN_IDENTITY to a signing identity to fix this." >&2
fi
echo "$APP"
