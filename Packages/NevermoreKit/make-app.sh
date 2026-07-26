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

# Embed Sparkle. SwiftPM links it as a dynamic framework via @rpath but only
# emits a bare Mach-O, so without this the wrapped app dies at launch with
# "Library not loaded: @rpath/Sparkle.framework". The framework carries its own
# XPC services and Autoupdate.app inside, which is why it is signed --deep and
# signed *before* the app that contains it.
if [ -d "$BIN_DIR/Sparkle.framework" ]; then
  mkdir -p "$APP/Contents/Frameworks"
  rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
  cp -R "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/"
  install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "$APP/Contents/MacOS/Nevermore" 2>/dev/null || true
fi
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
  <!-- __SPARKLE_KEYS__ -->
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
# Sparkle's feed and public key, only when a key has actually been generated.
# Without them Sparkle is inert rather than broken, so the app builds and runs
# fine before the signing key exists. A Mac App Store build must never contain
# these — it is a different target that doesn't link Sparkle at all.
SPARKLE_KEY_FILE="$(dirname "$0")/Resources/sparkle-public-key.txt"
if [ "${NEVERMORE_SANDBOX:-0}" != "1" ] && [ -s "$SPARKLE_KEY_FILE" ]; then
  SPARKLE_PUBLIC_KEY=$(tr -d ' \t\n\r' < "$SPARKLE_KEY_FILE")
  SPARKLE_FEED=${NEVERMORE_FEED_URL:-https://brooksc.github.io/nevermore/appcast.xml}
  /usr/bin/python3 - "$APP/Contents/Info.plist" "$SPARKLE_PUBLIC_KEY" "$SPARKLE_FEED" <<'PYEOF'
import sys
path, key, feed = sys.argv[1], sys.argv[2], sys.argv[3]
block = (
    "  <key>SUFeedURL</key><string>%s</string>\n"
    "  <key>SUPublicEDKey</key><string>%s</string>\n"
    "  <key>SUEnableInstallerLauncherService</key><false/>" % (feed, key)
)
s = open(path).read().replace("  <!-- __SPARKLE_KEYS__ -->", block)
open(path, "w").write(s)
PYEOF
  echo "sparkle: feed $SPARKLE_FEED" >&2
else
  /usr/bin/sed -i '' -e '/__SPARKLE_KEYS__/d' "$APP/Contents/Info.plist"
fi

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

# Inside out: nested code must be signed before whatever contains it.
if [ -d "$APP/Contents/Frameworks/Sparkle.framework" ] && [ -n "$SIGN_ID" ]; then
  codesign --force --deep --options runtime --sign "$SIGN_ID" \
    "$APP/Contents/Frameworks/Sparkle.framework"
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
