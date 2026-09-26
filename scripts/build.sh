#!/bin/zsh
# Builds NewFile.app (menu bar app + Finder Sync extension) for Intel and Apple silicon.
# Needs only the Command Line Tools — no Xcode.
#
#   scripts/build.sh                  # universal (arm64 + x86_64)
#   ARCHS=arm64 scripts/build.sh      # single slice
#   IDENTITY="Developer ID..." scripts/build.sh
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD="${NEWFILE_BUILD_DIR:-${TMPDIR:-/tmp}/newfile-build}"
APP="$BUILD/NewFile.app"
APPEX="$APP/Contents/PlugIns/NewFileFinder.appex"
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
    "$ROOT/Sources/Extension/FinderExtension.swift"
)
APP_SOURCES=(
    "$ROOT/Sources/App/main.swift"
    "$ROOT/Sources/App/Updater.swift"
    "$ROOT/Sources/Shared/ZipWriter.swift"
    "$ROOT/Sources/Shared/FileTemplates.swift"
    "$ROOT/Sources/Shared/DebugLog.swift"
    "$ROOT/Sources/Shared/FileCreator.swift"
)

echo "== SDK: $SDK"
echo "== architectures: $ARCHS (min macOS $MIN_MACOS)"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APPEX/Contents/MacOS" "$MODCACHE"

arch_binaries_finder=()
arch_binaries_app=()

for arch in ${=ARCHS}; do
    target="$arch-apple-macosx$MIN_MACOS"
    echo "== compiling $arch"

    xcrun swiftc -c -sdk "$SDK" -target "$target" -module-cache-path "$MODCACHE" -O \
        -whole-module-optimization -parse-as-library -module-name NewFileFinder \
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
        -module-name NewFile "${APP_SOURCES[@]}" \
        -framework AppKit -framework FinderSync -framework ServiceManagement \
        -o "$BUILD/app-$arch"
    arch_binaries_app+=("$BUILD/app-$arch")
done

echo "== linking universal binaries"
if (( ${#arch_binaries_finder[@]} > 1 )); then
    lipo -create -output "$APPEX/Contents/MacOS/NewFileFinder" "${arch_binaries_finder[@]}"
    lipo -create -output "$APP/Contents/MacOS/NewFile" "${arch_binaries_app[@]}"
else
    cp "${arch_binaries_finder[1]}" "$APPEX/Contents/MacOS/NewFileFinder"
    cp "${arch_binaries_app[1]}" "$APP/Contents/MacOS/NewFile"
fi
lipo -info "$APP/Contents/MacOS/NewFile"
lipo -info "$APPEX/Contents/MacOS/NewFileFinder"

cp "$ROOT/Resources/Info-app.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/Info-appex.plist" "$APPEX/Contents/Info.plist"
echo "== version $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"

echo "== signing (identity: $IDENTITY)"
xattr -cr "$APP"
codesign --force --sign "$IDENTITY" --timestamp=none \
    --entitlements "$ROOT/Resources/NewFileFinder.entitlements" "$APPEX"
# iCloud/Finder can re-add FinderInfo attributes between the two signing steps.
xattr -cr "$APP"
codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

echo "== built: $APP"
