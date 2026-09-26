#!/bin/zsh
# Builds Blanko.app (menu bar app + Finder Sync extension) for Intel and Apple silicon.
# Needs only the Command Line Tools — no Xcode.
#
#   scripts/build.sh                  # universal (arm64 + x86_64)
#   ARCHS=arm64 scripts/build.sh      # single slice
#   IDENTITY="Developer ID..." scripts/build.sh
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD="${BLANKO_BUILD_DIR:-${TMPDIR:-/tmp}/blanko-build}"
APP="$BUILD/Blanko.app"
APPEX="$APP/Contents/PlugIns/BlankoFinder.appex"
INSTALLER="$BUILD/Установить Blanko.app"
MODCACHE="$BUILD/.modulecache"
ARCHS="${ARCHS:-arm64 x86_64}"
MIN_MACOS="${MIN_MACOS:-13.0}"
IDENTITY="${IDENTITY:--}"

SDK="${SDK:-}"
if [[ -z "$SDK" ]]; then
    for candidate in MacOSX15.4.sdk MacOSX15.sdk MacOSX26.5.sdk MacOSX26.sdk MacOSX.sdk; do
        sdk_candidate="/Library/Developer/CommandLineTools/SDKs/$candidate"
        if [[ -d "$sdk_candidate" ]]; then SDK="$sdk_candidate"; break; fi
    done
fi
if [[ -z "$SDK" || ! -d "$SDK" ]]; then
    echo "error: macOS SDK not found. Install the Command Line Tools: xcode-select --install" >&2
    exit 1
fi

EXT_SOURCES=(
    "$ROOT/Sources/Shared/ZipWriter.swift"
    "$ROOT/Sources/Shared/FileTemplates.swift"
    "$ROOT/Sources/Shared/DebugLog.swift"
    "$ROOT/Sources/Shared/FileCreator.swift"
    "$ROOT/Sources/Shared/FileIcons.swift"
    "$ROOT/Sources/Extension/FinderExtension.swift"
)
APP_SOURCES=(
    "$ROOT/Sources/App/main.swift"
    "$ROOT/Sources/App/Updater.swift"
    "$ROOT/Sources/Shared/ZipWriter.swift"
    "$ROOT/Sources/Shared/FileTemplates.swift"
    "$ROOT/Sources/Shared/DebugLog.swift"
    "$ROOT/Sources/Shared/FileCreator.swift"
    "$ROOT/Sources/Shared/FileIcons.swift"
)

echo "== SDK: $SDK"
echo "== architectures: $ARCHS (min macOS $MIN_MACOS)"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APPEX/Contents/MacOS" "$MODCACHE"
mkdir -p "$APP/Contents/Resources" "$INSTALLER/Contents/MacOS" "$INSTALLER/Contents/Resources"

arch_binaries_finder=()
arch_binaries_app=()
arch_binaries_installer=()

for arch in ${=ARCHS}; do
    target="$arch-apple-macosx$MIN_MACOS"
    echo "== compiling $arch"

    xcrun swiftc -c -sdk "$SDK" -target "$target" -module-cache-path "$MODCACHE" -O \
        -whole-module-optimization -parse-as-library -module-name BlankoFinder \
        "${EXT_SOURCES[@]}" \
        -o "$BUILD/finder-$arch.o"

    xcrun clang -o "$BUILD/finder-$arch" \
        -e _NSExtensionMain \
        -target "$target" -isysroot "$SDK" \
        "$BUILD/finder-$arch.o" \
        -framework Foundation -framework AppKit -framework FinderSync \
        -L /usr/lib/swift -Xlinker -rpath -Xlinker /usr/lib/swift
    arch_binaries_finder+=("$BUILD/finder-$arch")

    xcrun swiftc -sdk "$SDK" -target "$target" -module-cache-path "$MODCACHE" -O \
        -module-name Blanko "${APP_SOURCES[@]}" \
        -framework AppKit -framework FinderSync -framework ServiceManagement \
        -o "$BUILD/app-$arch"
    arch_binaries_app+=("$BUILD/app-$arch")

    xcrun swiftc -sdk "$SDK" -target "$target" -module-cache-path "$MODCACHE" -O \
        -module-name BlankoInstaller "$ROOT/Sources/Installer/main.swift" \
        -framework AppKit \
        -o "$BUILD/installer-$arch"
    arch_binaries_installer+=("$BUILD/installer-$arch")
done

echo "== linking universal binaries"
if (( ${#arch_binaries_finder[@]} > 1 )); then
    lipo -create -output "$APPEX/Contents/MacOS/BlankoFinder" "${arch_binaries_finder[@]}"
    lipo -create -output "$APP/Contents/MacOS/Blanko" "${arch_binaries_app[@]}"
    lipo -create -output "$INSTALLER/Contents/MacOS/BlankoInstaller" "${arch_binaries_installer[@]}"
else
    cp "${arch_binaries_finder[1]}" "$APPEX/Contents/MacOS/BlankoFinder"
    cp "${arch_binaries_app[1]}" "$APP/Contents/MacOS/Blanko"
    cp "${arch_binaries_installer[1]}" "$INSTALLER/Contents/MacOS/BlankoInstaller"
fi
lipo -info "$APP/Contents/MacOS/Blanko"
lipo -info "$APPEX/Contents/MacOS/BlankoFinder"

cp "$ROOT/Resources/Info-app.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/Info-appex.plist" "$APPEX/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
echo "== version $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"

echo "== signing (identity: $IDENTITY)"
xattr -cr "$APP"
codesign --force --sign "$IDENTITY" --timestamp=none \
    --entitlements "$ROOT/Resources/BlankoFinder.entitlements" "$APPEX"
# iCloud/Finder can re-add FinderInfo attributes between the two signing steps.
xattr -cr "$APP"
codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

echo "== assembling installer app"
cp "$ROOT/Resources/Info-installer.plist" "$INSTALLER/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$INSTALLER/Contents/Resources/AppIcon.icns"
cp "$ROOT/scripts/install.sh" "$INSTALLER/Contents/Resources/install.sh"
ditto "$APP" "$INSTALLER/Contents/Resources/Blanko.app"
lipo -info "$INSTALLER/Contents/MacOS/BlankoInstaller"
xattr -cr "$INSTALLER"
codesign --force --sign "$IDENTITY" --timestamp=none "$INSTALLER"
codesign --verify --deep --strict "$INSTALLER"

echo "== built: $APP"
echo "== built: $INSTALLER"
