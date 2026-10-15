#!/bin/bash
# Builds Pastebird.app (Apple silicon + Intel) and packs it as a .dmg for users and a .zip for the updater.
#   bash mac/build.sh
# Output in mac/build/: Pastebird.app, Pastebird-<version>.dmg and Pastebird-mac-<version>.zip.
#
# Without SIGN_IDENTITY the app is signed ad hoc. Its designated requirement then only names the bundle identifier,
# so macOS keeps the Accessibility permission and the Keychain access after an update.
# With SIGN_IDENTITY="Developer ID Application: …" it is signed for distribution (with the hardened runtime).
# With NOTARY_KEY (path to an App Store Connect API key, AuthKey_….p8), NOTARY_KEY_ID and NOTARY_ISSUER as well,
# the app and the disk image are notarized by Apple and stapled, so Gatekeeper opens them without a warning.
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"
BUNDLE_ID="app.pastebird.Pastebird"

# One version for Windows and macOS: <Version> in the Windows project.
VERSION="$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' "$ROOT/src/Pastebird/Pastebird.csproj" | head -1)"
if [ -z "$VERSION" ]; then echo "No <Version> found in Pastebird.csproj" >&2; exit 1; fi
echo "Building Pastebird $VERSION for macOS"

NOTARIZE=false
if [ -n "${SIGN_IDENTITY:-}" ] && [ -n "${NOTARY_KEY:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER:-}" ]; then
    NOTARIZE=true
fi

# Sends a file to Apple's notary service and waits for the verdict (usually a few minutes).
notarize() {
    local result id
    result="$(xcrun notarytool submit "$1" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" \
        --wait --output-format json)"
    echo "$result"
    if ! echo "$result" | grep -q '"status" *: *"Accepted"'; then
        id="$(echo "$result" | sed -n 's/.*"id" *: *"\([^"]*\)".*/\1/p')"
        [ -n "$id" ] && xcrun notarytool log "$id" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" || true
        echo "Notarization of $1 failed" >&2
        exit 1
    fi
}

swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

OUT="build"
APP="$OUT/Pastebird.app"
rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/Pastebird" "$APP/Contents/MacOS/Pastebird"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
# Shown in "What's new" after an update (Core/Changelog.swift).
cp "$ROOT/CHANGELOG.md" "$APP/Contents/Resources/CHANGELOG.md"
# UI languages, shared with Windows (Core/Localization.swift, docs/TRANSLATING.md).
mkdir -p "$APP/Contents/Resources/Languages"
cp "$ROOT"/src/Pastebird/Languages/*.json "$APP/Contents/Resources/Languages/"
iconutil -c icns Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force --sign - --requirements "=designated => identifier \"$BUNDLE_ID\"" "$APP"
fi
codesign --verify --strict "$APP"

if $NOTARIZE; then
    ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
    notarize "$OUT/notarize.zip"
    rm "$OUT/notarize.zip"
    xcrun stapler staple "$APP"
    spctl --assess --type execute --verbose "$APP"
fi

# Updater package: the app in a zip, as the built-in updater expects it (Services/UpdateService.swift).
ditto -c -k --keepParent "$APP" "$OUT/Pastebird-mac-$VERSION.zip"

# Disk image for users: drag Pastebird to Applications.
DMG="$OUT/Pastebird-$VERSION.dmg"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Pastebird" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi
if $NOTARIZE; then
    notarize "$DMG"
    xcrun stapler staple "$DMG"
fi

echo "Done$($NOTARIZE && echo ", signed and notarized" || true):"
ls -lh "$OUT"
