#!/bin/zsh
# Builds a release, updates the update manifest and (with --push) publishes it.
#
#   scripts/release.sh 1.2.0 "Что нового"
#   scripts/release.sh 1.2.0 "Что нового" --push
#
# Without --push everything happens locally: version bump, build, manifest,
# commits on main + release and a tag. Nothing is sent to GitHub.
set -euo pipefail

ROOT="${0:A:h:h}"
REPO_SLUG="timka-robin/blanko"
VERSION="${1:?usage: scripts/release.sh <version> [notes] [--push]}"
NOTES="${2:-}"
PUSH=0
for arg in "$@"; do [[ "$arg" == "--push" ]] && PUSH=1; done

DIST="$ROOT/dist"
BUILD="${BLANKO_BUILD_DIR:-${TMPDIR:-/tmp}/blanko-build}"
APP="$BUILD/Blanko.app"
ZIP="$DIST/Blanko.app.zip"
ASSET_URL="https://github.com/$REPO_SLUG/releases/download/v$VERSION/Blanko.app.zip"

cd "$ROOT"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "warning: working tree is not clean, continuing anyway"
fi

echo "== 1/6 version"
./scripts/version.sh "$VERSION"

echo "== 2/6 build"
./scripts/build.sh

echo "== 3/6 package"
mkdir -p "$DIST"
STAGE="$DIST/Blanko-$VERSION"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Blanko.app"
cp "$ROOT/scripts/install.command" "$STAGE/Установить.command"
chmod +x "$STAGE/Установить.command"
rm -f "$ZIP"
# zip the *contents* of the staging folder so Blanko.app stays at the archive root;
# plain zip keeps the archive free of __MACOSX noise and keeps the exec bit
(cd "$STAGE" && zip -qry -y -X "$ZIP" Blanko.app "Установить.command")
rm -rf "$STAGE"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "   $ZIP"
echo "   sha256 $SHA"

echo "== 3b/6 disk image"
./scripts/make-dmg.sh
DMG="$DIST/Blanko-$VERSION.dmg"
echo "   $DMG"
# A .dmg keeps its custom icon only while its file attributes travel with it;
# a ditto-made zip carries them along, so a downloaded copy still looks right.
DMGZIP="$DIST/Blanko-$VERSION.dmg.zip"
rm -f "$DMGZIP"
(cd "$DIST" && ditto -c -k --sequesterRsrc "Blanko-$VERSION.dmg" "$DMGZIP")
echo "   $DMGZIP"

echo "== 4/6 manifest"
/usr/bin/python3 - "$ROOT/update.json" "$VERSION" "$ASSET_URL" "$SHA" "$NOTES" <<'PY'
import json, sys
path, version, url, sha, notes = sys.argv[1:6]
payload = {"version": version, "url": url, "sha256": sha, "notes": notes}
with open(path, "w") as fh:
    json.dump(payload, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
print(open(path).read().strip())
PY

echo "== 5/6 commits"
git add Resources/Info-app.plist Resources/Info-appex.plist Resources/Info-installer.plist
git commit -m "Bump version to $VERSION" || echo "   (nothing to commit)"

# The manifest lives on main; the release branch always mirrors main, so users
# updating from `release` see exactly the released tree.
git add update.json
git commit -m "Release $VERSION" || echo "   (nothing to commit)"

if ! git rev-parse --verify --quiet release >/dev/null; then
    git branch release
fi
git checkout release
git merge --no-edit -X theirs main
git tag -f "v$VERSION"
git checkout -

echo "== 6/6 publish"
if (( PUSH )); then
    git push origin main
    git push origin release
    git push origin "v$VERSION" --force
    gh release create "v$VERSION" "$ZIP" "$DMG" "$DMGZIP" \
        --repo "$REPO_SLUG" \
        --title "v$VERSION" \
        --notes "${NOTES:-Release $VERSION}"
    echo "== published: https://github.com/$REPO_SLUG/releases/tag/v$VERSION"
else
    echo "== local only (no --push). Artefacts:"
    echo "   $ZIP"
    echo "   $DMG"
    echo "   $DMGZIP"
    echo "   $ROOT/update.json (committed on the release branch)"
fi
