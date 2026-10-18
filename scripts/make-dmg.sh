#!/bin/zsh
# Builds dist/Blanko-<version>.dmg: the app, the installer app, an Applications
# alias and the volume icon. Needs scripts/build.sh to have run first.
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD="${BLANKO_BUILD_DIR:-${TMPDIR:-/tmp}/blanko-build}"
APP="$BUILD/Blanko.app"
INSTALLER="$BUILD/Установить Blanko.app"
DIST="$ROOT/dist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info-app.plist")"
DMG="$DIST/Blanko-$VERSION.dmg"
STAGE="$BUILD/dmg"
RW="$BUILD/Blanko-rw.dmg"

if [[ ! -d "$APP" ]]; then
    echo "error: $APP not found. Run scripts/build.sh first." >&2
    exit 1
fi
if [[ ! -d "$INSTALLER" ]]; then
    echo "error: $INSTALLER not found." >&2
    exit 1
fi

echo "== staging"
rm -rf "$STAGE" "$RW" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Blanko.app"
ditto "$INSTALLER" "$STAGE/Установить Blanko.app"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
xattr -cr "$STAGE" 2>/dev/null || true

echo "== creating image"
hdiutil create -volname "Blanko $VERSION" -srcfolder "$STAGE" -ov -format UDRW -quiet "$RW"

MOUNT="$(mktemp -d)"
hdiutil attach "$RW" -nobrowse -noverify -noautoopen -mountpoint "$MOUNT" -quiet
# marks the mounted volume as having a custom icon (.VolumeIcon.icns)
SetFile -a C "$MOUNT"
hdiutil detach "$MOUNT" -quiet
rmdir "$MOUNT" 2>/dev/null || true

echo "== compressing"
hdiutil convert "$RW" -format UDZO -o "$DMG" -quiet
rm -f "$RW"
rm -rf "$STAGE"

echo "== attaching the icon to the image file itself"
ICON_WORK="$BUILD/dmg-icon"
rm -f "$ICON_WORK.icns" "$ICON_WORK.rsrc"
cp "$ROOT/Resources/AppIcon.icns" "$ICON_WORK.icns"
sips -i "$ICON_WORK.icns" >/dev/null
DeRez -only icns "$ICON_WORK.icns" > "$ICON_WORK.rsrc"
Rez -append "$ICON_WORK.rsrc" -o "$DMG"
SetFile -a C "$DMG"
rm -f "$ICON_WORK.icns" "$ICON_WORK.rsrc"

echo "== built: $DMG"
