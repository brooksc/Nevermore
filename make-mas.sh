#!/bin/bash
# Build the Mac App Store package, and optionally upload it.
#
#   ./make-mas.sh            # build + verify, leaves build/export-mas/Nevermore.pkg
#   ./make-mas.sh --upload   # ...then deliver it to App Store Connect
#
# This is the store channel only. make-app.sh and make-dmg.sh remain the
# Developer ID path and are untouched by this script.
set -euo pipefail
cd "$(dirname "$0")"

UPLOAD=0
[ "${1:-}" = "--upload" ] && UPLOAD=1

# ---------------------------------------------------------------------------
# Toolchain guard. This exists because it already cost an evening.
#
# App Store ingestion rejects anything built with a beta Xcode — error 90301,
# "Apple is not currently accepting applications built with this version of
# Xcode" — checked server-side against the DTXcodeBuild/DTSDKBuild keys the
# toolchain stamps into Info.plist. Nothing about the upload can work around
# it; the bundle has to be rebuilt.
#
# What makes it a trap rather than an inconvenience: notarization has no such
# check, so the same beta-built code sails through the DMG pipeline. Every
# other script here defaults DEVELOPER_DIR to Xcode-beta, which is right for
# Developer ID and silently wrong for the store. Hence: refuse rather than
# build something Apple will bounce.
# ---------------------------------------------------------------------------
find_release_xcode() {
    # NEVERMORE_MAS_XCODE wins, so an unusual install location needs no edit here.
    local candidates=(
        "${NEVERMORE_MAS_XCODE:-}"
        /Applications/Xcode.app
        /Applications/Xcode_*.app
        "$HOME/Downloads/Xcode.app"
    )
    for app in "${candidates[@]}"; do
        [ -n "$app" ] && [ -d "$app/Contents/Developer" ] || continue
        # The expanded .xip may live anywhere; what disqualifies it is being a
        # beta, which the bundle name is the only reliable signal for —
        # `xcodebuild -version` prints no "beta" marker.
        case "$(echo "$app" | tr '[:upper:]' '[:lower:]')" in
            *beta*) continue ;;
        esac
        echo "$app/Contents/Developer"
        return 0
    done
    return 1
}

if ! DEVELOPER_DIR=$(find_release_xcode); then
    cat >&2 <<'EOF'
No released Xcode found — refusing to build a store package with a beta.

App Store ingestion rejects beta-built binaries (error 90301). Notarization
does not, so the DMG channel will keep working regardless; this only blocks
the store.

On a macOS beta the Mac App Store will not install a released Xcode ("This
version of Xcode isn't supported in this version of macOS"). Get it directly:

  1. https://developer.apple.com/download/all/  →  Xcode 26.x  →  .xip
  2. xip --expand Xcode_26.6_Apple_silicon.xip     (needs ~20 GB free)
  3. The IDE may refuse to launch on a beta OS. That does not matter — only
     xcodebuild is needed, and it runs.
  4. Re-run, or point at it: NEVERMORE_MAS_XCODE=/path/to/Xcode.app ./make-mas.sh

See MAS-RELEASE.md §8.5.
EOF
    exit 1
fi
export DEVELOPER_DIR
echo "toolchain: $(xcodebuild -version | tr '\n' ' ')" >&2
echo "           $DEVELOPER_DIR" >&2

# App Store Connect enforces a strictly increasing CFBundleVersion per upload.
# The commit count is what the DMG uses too, so the channels agree.
BUILD_NUMBER=${NEVERMORE_BUILD:-$(git rev-list --count HEAD)}
PROFILE_NAME=${NEVERMORE_MAS_PROFILE_NAME:-Nevermore Mac App Store}

rm -rf build
TUIST_BUILD_NUMBER="$BUILD_NUMBER" TUIST_MAS_PROFILE_NAME="$PROFILE_NAME" \
    tuist generate --no-open >/dev/null

xcodebuild archive \
    -workspace Nevermore.xcworkspace \
    -scheme Nevermore \
    -configuration Release \
    -archivePath build/Nevermore-MAS.xcarchive \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Apple Distribution" \
    DEVELOPMENT_TEAM=SU999VT2G2 \
    | grep -E "error:|ARCHIVE" || true

APP="build/Nevermore-MAS.xcarchive/Products/Applications/Nevermore.app"
[ -d "$APP" ] || { echo "archive failed" >&2; exit 1; }

# Everything below fails in seconds; the alternative is finding out after
# ingestion, or worse, after review.
fail() { echo "PREFLIGHT FAILED: $1" >&2; exit 1; }

# Apple rejects apps that update themselves. Project.swift declares no Sparkle
# package at all, so this should be structurally impossible — which is exactly
# why it's worth asserting rather than assuming.
otool -L "$APP/Contents/MacOS/Nevermore" | grep -qi sparkle \
    && fail "Sparkle is linked into the store build"
[ -d "$APP/Contents/Frameworks/Sparkle.framework" ] \
    && fail "Sparkle.framework is embedded in the store build"

[ -f "$APP/Contents/embedded.provisionprofile" ] \
    || fail "no embedded.provisionprofile — signing did not use the profile"
codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q "app-sandbox" \
    || fail "the app-sandbox entitlement is missing"

# The check that would have caught error 90301 before the upload.
DT_XCODE_BUILD=$(/usr/libexec/PlistBuddy -c "Print DTXcodeBuild" "$APP/Contents/Info.plist")
DT_SDK=$(/usr/libexec/PlistBuddy -c "Print DTSDKName" "$APP/Contents/Info.plist")
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")

echo "preflight: ok — $VERSION ($BUILD_NUMBER), $(lipo -archs "$APP/Contents/MacOS/Nevermore")" >&2
echo "           DTXcodeBuild $DT_XCODE_BUILD, SDK $DT_SDK, no Sparkle, profile embedded" >&2

INSTALLER=$(security find-identity -v \
    | awk -F'"' '/3rd Party Mac Developer Installer/{print $2; exit}')
[ -n "$INSTALLER" ] || fail "no '3rd Party Mac Developer Installer' identity in the keychain"

mkdir -p build/export-mas
PKG=build/export-mas/Nevermore.pkg
# productbuild rather than `xcodebuild -exportArchive`: the app is already
# signed by the archive step, exportArchive needs an exportOptions.plist to
# maintain, and it is the step that fails on GitHub's runners with
# "Unknown Distribution Error". This wraps the signed app and nothing else.
#
# productbuild prints "write: Permission denied" to stderr a few times on this
# machine no matter how its streams are redirected. It still exits 0 and the
# package verifies, so it is noise — but noise that reads like a failure in a
# release script, which is worse than useless. Filtered, not hidden: anything
# else productbuild says still comes through.
productbuild --component "$APP" /Applications --sign "$INSTALLER" "$PKG" 2>&1 \
    | grep -v "^write: Permission denied" >&2
echo "packaged: $PKG" >&2

if [ "$UPLOAD" = "1" ]; then
    # Key IDs are not secrets; the .p8 they name is, and it stays out of the
    # repo. See MAS-RELEASE.md §7.
    KEY=${NEVERMORE_ASC_KEY_ID:-68BGNV3CCC}
    ISSUER=${NEVERMORE_ASC_ISSUER_ID:-7ab554b4-f208-4c99-9003-30c1320a3262}
    [ -f "$HOME/.appstoreconnect/private_keys/AuthKey_$KEY.p8" ] \
        || fail "missing ~/.appstoreconnect/private_keys/AuthKey_$KEY.p8"
    echo "uploading to App Store Connect…" >&2
    xcrun altool --upload-app --type macos --file "$PKG" \
        --apiKey "$KEY" --apiIssuer "$ISSUER"
else
    echo "NOT uploaded — re-run with --upload, or deliver $PKG by hand." >&2
fi

echo "$PKG"
