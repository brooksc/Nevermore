#!/bin/bash
# Build a distributable DMG: a signed, notarized, stapled disk image with the
# app and a symlink to /Applications.
#
#   ./make-dmg.sh            # build + package (unnotarized, for local testing)
#   ./make-dmg.sh --notarize # build + package + notarize + staple
#
# Notarizing needs credentials stored once:
#   xcrun notarytool store-credentials nevermore-notary \
#     --apple-id "you@example.com" --team-id SU999VT2G2
#   # paste an app-specific password from appleid.apple.com when prompted
#
# The DMG is what GitHub Releases serves and what Sparkle downloads. It is NOT
# the Mac App Store artifact — that comes from the Xcode app target, unsigned by
# this script and without Sparkle. See MAS-RELEASE.md.
set -euo pipefail

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
cd "$(dirname "$0")"

NOTARIZE=0
[ "${1:-}" = "--notarize" ] && NOTARIZE=1
PROFILE=${NEVERMORE_NOTARY_PROFILE:-nevermore-notary}

VERSION=$(tr -d ' \t\n\r' < VERSION)

# Refuse to package a build whose version disagrees with the tag on HEAD.
TAG=$(git describe --exact-match --tags 2>/dev/null || true)
if [ -n "$TAG" ] && [ "$TAG" != "v$VERSION" ]; then
  echo "VERSION is $VERSION but HEAD is tagged $TAG — expected v$VERSION." >&2
  exit 1
fi

# ...and one whose version has nothing to say for itself. The tag guard above
# catches a version that disagrees with the tag; nothing caught a release with
# no changelog entry, and CHANGELOG.md is the source for both the GitHub release
# notes and the App Store "What's New". Shipping without one means writing the
# notes from memory afterwards, which is when they get thin.
CHANGELOG="$(dirname "$0")/../../CHANGELOG.md"
if [ -f "$CHANGELOG" ] && ! grep -qE "^## \[$VERSION\]" "$CHANGELOG"; then
  echo "CHANGELOG.md has no '## [$VERSION]' entry." >&2
  echo "Add one before packaging — it is where the release notes come from." >&2
  exit 1
fi

APP=$(./make-app.sh release | tail -1)
echo "built: $APP" >&2

# Notarize and staple the .app *before* it goes into the image. Stapling only
# the DMG is enough for someone who downloads it — Gatekeeper checks the image —
# but Sparkle installs the .app it extracts from that image, and an unstapled
# app has to reach Apple's servers to prove it's notarized. On a machine that's
# offline or behind a filter, that's a launch failure after an update. The app
# can't be stapled once it's inside a read-only image, hence the separate
# submission here.
if [ "$NOTARIZE" = "1" ]; then
  ZIP="${APP%.app}.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "submitting the app to Apple (this can take a few minutes)…" >&2
  xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
  rm -f "$ZIP"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  echo "app notarized and stapled" >&2
fi

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

DMG="$(dirname "$APP")/Nevermore-$VERSION.dmg"
rm -f "$DMG"

# UDZO is the compressed read-only format every Mac can mount without extra
# tooling; the volume name is what shows in Finder's sidebar when opened.
hdiutil create -volname "Nevermore $VERSION" -srcfolder "$STAGE" \
  -ov -format UDZO -quiet "$DMG"

# Sign the image itself, so Gatekeeper can check it before it is mounted.
SIGN_ID="${NEVERMORE_SIGN_IDENTITY:-}"
if [ -z "$SIGN_ID" ]; then
  SIGN_ID=$(security find-identity -v -p codesigning \
    | awk -F'"' '/Developer ID Application/{print $2; exit}')
fi
if [ -n "$SIGN_ID" ]; then
  codesign --force --sign "$SIGN_ID" "$DMG"
  echo "signed dmg: $SIGN_ID" >&2
else
  echo "WARNING: no Developer ID cert; the DMG is unsigned and Gatekeeper" >&2
  echo "         will refuse it on other Macs." >&2
fi

if [ "$NOTARIZE" = "1" ]; then
  echo "submitting the image to Apple (this can take a few minutes)…" >&2
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  # Staple to the DMG so it validates with no network on the user's machine.
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  echo "notarized and stapled" >&2
else
  echo "NOT notarized — fine locally, but Gatekeeper will block it on any" >&2
  echo "other Mac. Re-run with --notarize before publishing." >&2
fi

echo "$DMG"
