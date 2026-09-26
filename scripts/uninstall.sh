#!/bin/zsh
# Removes the installed app and forgets the Finder extension.
set -euo pipefail

DEST="/Applications/NewFile.app"
APPEX_ID="com.timurgizatullin.newfile.finder"

pluginkit -r "$DEST/Contents/PlugIns/NewFileFinder.appex" 2>/dev/null || true
pkill -f "$DEST/Contents/MacOS/NewFile" 2>/dev/null || true
rm -rf "$DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -kill -r -domain local -domain system -domain user >/dev/null 2>&1 || true

echo "removed $DEST (extension id $APPEX_ID)"
echo "note: turn off 'Запускать при входе' in the app before removing it,"
echo "      otherwise the login item stays in System Settings."
