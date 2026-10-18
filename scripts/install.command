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

LANG_CODE="$(defaults read -g AppleLanguages 2>/dev/null | sed -n '1s/.*"\([^"-]*\).*/\1/p')"
if [[ "$LANG_CODE" != "ru" ]]; then
    LANG_CODE="en"
fi

msg() {
    local key="$1"
    if [[ "$LANG_CODE" == "ru" ]]; then
        case "$key" in
            missing) echo "Рядом с этим файлом нет Blanko.app." ;;
            stopping) echo "== останавливаю запущенную копию" ;;
            copying) echo "== копирую в /Applications" ;;
            registering) echo "== регистрирую расширение Finder" ;;
            launching) echo "== запускаю приложение" ;;
            done1) echo "Готово. Правый клик в локальной папке — пункты в меню," ;;
            done2) echo "в iCloud и на рабочем столе — Службы, а также ⌃⌥⌘1/2/3." ;;
        esac
    else
        case "$key" in
            missing) echo "Blanko.app is not next to this file." ;;
            stopping) echo "== stopping the running copy" ;;
            copying) echo "== copying to /Applications" ;;
            registering) echo "== registering the Finder extension" ;;
            launching) echo "== launching the app" ;;
            done1) echo "Done. Right-click in a local folder to see the items in the menu;" ;;
            done2) echo "in iCloud and on the desktop use Services, or press ⌃⌥⌘1/2/3." ;;
        esac
    fi
}

pause() {
    echo
    if [[ "$LANG_CODE" == "ru" ]]; then
        read -s -k 1 "?Нажми любую клавишу, чтобы закрыть это окно…"
    else
        read -s -k 1 "?Press any key to close this window…"
    fi
    echo
}

if [[ ! -d "$SOURCE" ]]; then
    msg missing
    pause
    exit 1
fi

msg stopping
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

msg copying
ditto "$SOURCE" "$DEST"
# снимаем карантин, иначе macOS не даст запустить приложение без Developer ID
xattr -cr "$DEST"

msg registering
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
pluginkit -a "$DEST/Contents/PlugIns/BlankoFinder.appex"
pluginkit -e use -i "$APPEX_ID"
pluginkit -e ignore -i "$LEGACY_APPEX_ID" 2>/dev/null || true

msg launching
open -g "$DEST"

echo
msg done1
msg done2
pause
