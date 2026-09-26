#!/bin/zsh
# Installs Blanko.app into /Applications and enables the Finder extension.
set -euo pipefail

ROOT="${0:A:h:h}"
SOURCE="${BLANKO_BUILD_DIR:-${TMPDIR:-/tmp}/blanko-build}/Blanko.app"
DEST="/Applications/Blanko.app"
APPEX_ID="com.blanko.mac.finder"
LEGACY_APPEX_ID="com.timurgizatullin.newfile.finder"

if [[ ! -d "$SOURCE" ]]; then
    echo "error: $SOURCE not found. Run scripts/build.sh first." >&2
    exit 1
fi

# Replacing a running copy: quit it first, otherwise the swap can fail.
pkill -f "$DEST/Contents/MacOS/Blanko" 2>/dev/null || true
pkill -f "$DEST/Contents/PlugIns/BlankoFinder.appex/Contents/MacOS/BlankoFinder" 2>/dev/null || true

# Drop a copy installed under the pre-rename name, so two builds never coexist.
LEGACY="/Applications/NewFile.app"
if [[ -d "$LEGACY" ]]; then
    echo "== removing the legacy copy at $LEGACY"
    pkill -f "$LEGACY/Contents/MacOS/NewFile" 2>/dev/null || true
    pluginkit -r "$LEGACY/Contents/PlugIns/NewFileFinder.appex" 2>/dev/null || true
    rm -rf "$LEGACY"
fi

sleep 1

echo "== installing to $DEST"
ditto "$SOURCE" "$DEST"
# Also drops the quarantine attribute of a downloaded archive.
xattr -cr "$DEST"

echo "== registering with LaunchServices"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"

echo "== registering the Finder extension"
pluginkit -a "$DEST/Contents/PlugIns/BlankoFinder.appex"
pluginkit -e use -i "$APPEX_ID"
# the pre-1.2.0 identity is no longer used
pluginkit -e ignore -i "$LEGACY_APPEX_ID" 2>/dev/null || true

echo "== launching the app once (required by macOS)"
open -g "$DEST"

echo "== extension state"
pluginkit -m -A -D -v -i "$APPEX_ID"
echo
echo "If the new items do not show up in Finder:"
echo "  killall Finder"
echo "or enable the extension in System Settings -> General -> Login Items & Extensions."
