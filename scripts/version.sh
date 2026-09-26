#!/bin/zsh
# Reads or sets the application version.
#
#   scripts/version.sh            -> prints the current version
#   scripts/version.sh 1.2.0      -> writes it into both Info.plist files
set -euo pipefail

ROOT="${0:A:h:h}"
PB=/usr/libexec/PlistBuddy
APP_PLIST="$ROOT/Resources/Info-app.plist"
EXT_PLIST="$ROOT/Resources/Info-appex.plist"
INSTALLER_PLIST="$ROOT/Resources/Info-installer.plist"

if [[ $# -eq 0 ]]; then
    "$PB" -c "Print :CFBundleShortVersionString" "$APP_PLIST"
    exit 0
fi

VERSION="$1"
if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo "error: version must look like 1.2.3" >&2
    exit 1
fi

BUILD_NUMBER="$(date +%Y%m%d%H%M)"

for plist in "$APP_PLIST" "$EXT_PLIST" "$INSTALLER_PLIST"; do
    [[ -f "$plist" ]] || continue
    "$PB" -c "Set :CFBundleShortVersionString $VERSION" "$plist"
    "$PB" -c "Set :CFBundleVersion $BUILD_NUMBER" "$plist"
done

echo "version set to $VERSION (build $BUILD_NUMBER)"
