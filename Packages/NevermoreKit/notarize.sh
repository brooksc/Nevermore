#!/bin/bash
# Notarize the release build for distribution to other Macs.
#
# One-time setup (stores your Apple ID app-specific password in the keychain so
# it isn't passed on the command line):
#   xcrun notarytool store-credentials nevermore-notary \
#     --apple-id "you@example.com" --team-id "YOUR_TEAM_ID"
#   # (paste an app-specific password from appleid.apple.com when prompted)
#
# Then just run:  ./notarize.sh
#
# This is a release action that uploads the app to Apple — run it yourself when
# you're ready to distribute; it is not part of the normal build.
set -euo pipefail

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
PROFILE=${NEVERMORE_NOTARY_PROFILE:-nevermore-notary}

cd "$(dirname "$0")"

# 0. Refuse to ship a build whose version disagrees with the tag being
#    released. Shipping 0.1.0 under a v0.2.0 tag is the kind of mistake that is
#    invisible until someone reports a bug against a version that never existed.
VERSION=$(tr -d ' \t\n\r' < VERSION)
TAG=$(git describe --exact-match --tags 2>/dev/null || true)
if [ -n "$TAG" ] && [ "$TAG" != "v$VERSION" ]; then
  echo "VERSION is $VERSION but HEAD is tagged $TAG — expected v$VERSION." >&2
  echo "Fix VERSION or the tag before releasing." >&2
  exit 1
fi
if [ -z "$TAG" ]; then
  echo "warning: HEAD is not tagged; releasing $VERSION anyway" >&2
fi

# 1. Build the signed .app (release, Developer ID, hardened runtime).
APP=$(CONFIG=release ./make-app.sh release | tail -1)
echo "built: $APP"

# 2. Zip it (notarytool wants a zip or dmg).
ZIP="${APP%.app}.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# 3. Submit and wait for Apple's verdict.
echo "submitting to Apple (this can take a few minutes)…"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

# 4. Staple the ticket so it validates offline.
xcrun stapler staple "$APP"
xcrun stapler validate "$APP" && echo "notarized and stapled: $APP"

# 5. Fresh zip of the stapled app for distribution.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "distributable: $ZIP"
