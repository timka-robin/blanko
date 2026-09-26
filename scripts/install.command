#!/bin/zsh
# Double-click installer shipped inside the release archive.
# Copies Blanko.app (lying next to this script) into /Applications and,
# enables the Finder extension and launches the app.
set -e

HERE="${0:A:h}"
SOURCE="$HERE/Blanko.app"
DEST="/Applications/Blanko.app"
APPEX_ID="com.blanko.mac.finder"
LEGACY_APPEX_ID="com.timurgizatullin.newfile.finder"

pause() {
    echo
    read -s -k 1 "?Нажми любую клавишу, чтобы закрыть это окно…"
    echo
}

if [[ ! -d "$SOURCE" ]]; then
    echo "Рядом с этим файлом нет Blanko.app."
    pause
    exit 1
fi

echo "== останавливаю запущенную копию"
pkill -f "$DEST/Contents/MacOS/Blanko" 2>/dev/null || true
pkill -f "$DEST/Contents/PlugIns/BlankoFinder.appex/Contents/MacOS/BlankoFinder" 2>/dev/null || true

# сносим копию, установленную под старым именем (до переименования в Blanko)
LEGACY="/Applications/NewFile.app"
if [[ -d "$LEGACY" ]]; then
    pkill -f "$LEGACY/Contents/MacOS/NewFile" 2>/dev/null || true
    pluginkit -r "$LEGACY/Contents/PlugIns/NewFileFinder.appex" 2>/dev/null || true
    rm -rf "$LEGACY"
fi

sleep 1

echo "== копирую в /Applications"
ditto "$SOURCE" "$DEST"
# снимаем карантин, иначе macOS не даст запустить приложение без Developer ID
xattr -cr "$DEST"

echo "== регистрирую расширение Finder"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
pluginkit -a "$DEST/Contents/PlugIns/BlankoFinder.appex"
pluginkit -e use -i "$APPEX_ID"
pluginkit -e ignore -i "$LEGACY_APPEX_ID" 2>/dev/null || true

echo "== запускаю приложение"
open -g "$DEST"

echo
echo "Готово. Правый клик в локальной папке — пункты в меню,"
echo "в iCloud и на рабочем столе — Службы, а также ⌃⌥⌘1/2/3."
pause
