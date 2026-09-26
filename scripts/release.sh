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
REPO_SLUG="timka-robin/newfilemac"
VERSION="${1:?usage: scripts/release.sh <version> [notes] [--push]}"
NOTES="${2:-}"
PUSH=0
for arg in "$@"; do [[ "$arg" == "--push" ]] && PUSH=1; done

DIST="$ROOT/dist"
BUILD="${NEWFILE_BUILD_DIR:-${TMPDIR:-/tmp}/newfile-build}"
APP="$BUILD/NewFile.app"
ZIP="$DIST/NewFile.app.zip"
ASSET_URL="https://github.com/$REPO_SLUG/releases/download/v$VERSION/NewFile.app.zip"

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
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "   $ZIP"
echo "   sha256 $SHA"

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
git add Resources/Info-app.plist Resources/Info-appex.plist
git commit -m "Bump version to $VERSION" || echo "   (nothing to commit)"

# The manifest lives on main; the release branch always mirrors main, so users
# updating from `release` see exactly the released tree.
git add update.json
git commit -m "Release $VERSION" || echo "   (nothing to commit)"

if ! git rev-parse --verify --quiet release >/dev/null; then
    git branch release
fi
git checkout release
git merge --no-edit main
git tag -f "v$VERSION"
git checkout -

echo "== 6/6 publish"
if (( PUSH )); then
    git push origin main
    git push origin release
    git push origin "v$VERSION" --force
    gh release create "v$VERSION" "$ZIP" \
        --repo "$REPO_SLUG" \
        --title "v$VERSION" \
        --notes "${NOTES:-Release $VERSION}"
    echo "== published: https://github.com/$REPO_SLUG/releases/tag/v$VERSION"
else
    echo "== local only (no --push). Artefacts:"
    echo "   $ZIP"
    echo "   $ROOT/update.json (committed on the release branch)"
fi
