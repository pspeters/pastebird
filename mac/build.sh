#!/bin/bash
# Builds Pastebird.app (Apple silicon + Intel) and packs it as a .dmg for users and a .zip for the updater.
#   bash mac/build.sh
# Output in mac/build/: Pastebird.app, Pastebird-<version>.dmg and Pastebird-mac-<version>.zip.
#
# Without SIGN_IDENTITY the app is signed ad hoc. Its designated requirement then only names the bundle identifier,
# so macOS keeps the Accessibility permission and the Keychain access after an update.
# With SIGN_IDENTITY="Developer ID Application: …" it is signed for distribution (with the hardened runtime).
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"
BUNDLE_ID="app.pastebird.Pastebird"

# One version for Windows and macOS: <Version> in the Windows project.
VERSION="$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' "$ROOT/src/Pastebird/Pastebird.csproj" | head -1)"
if [ -z "$VERSION" ]; then echo "No <Version> found in Pastebird.csproj" >&2; exit 1; fi
echo "Building Pastebird $VERSION for macOS"

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
iconutil -c icns Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force --sign - --requirements "=designated => identifier \"$BUNDLE_ID\"" "$APP"
fi
codesign --verify --strict "$APP"

# Updater package: the app in a zip, as the built-in updater expects it (Services/UpdateService.swift).
ditto -c -k --keepParent "$APP" "$OUT/Pastebird-mac-$VERSION.zip"

# Disk image for users: drag Pastebird to Applications.
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Pastebird" -srcfolder "$STAGE" -ov -format UDZO "$OUT/Pastebird-$VERSION.dmg" >/dev/null
rm -rf "$STAGE"

echo "Done:"
ls -lh "$OUT"
