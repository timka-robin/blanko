#!/usr/bin/env python3
"""Fails when a Localizable.strings file is missing keys the others have."""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILES = sorted((ROOT / "Resources" / "strings").glob("*.lproj/Localizable.strings"))
INSTALLER_ROOT = ROOT / "Resources" / "installer"
KEY_PATTERN = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"', re.MULTILINE)


def keys_of(path: pathlib.Path) -> set[str]:
    return set(KEY_PATTERN.findall(path.read_text(encoding="utf-8")))


def main() -> int:
    if not FILES:
        print("no Localizable.strings found", file=sys.stderr)
        return 1

    reference = keys_of(FILES[0])
    failed = False
    for path in FILES:
        current = keys_of(path)
        missing = sorted(reference - current)
        extra = sorted(current - reference)
        if missing or extra:
            failed = True
            language = path.parent.name.removesuffix(".lproj")
            print(f"{language}: missing {missing} extra {extra}", file=sys.stderr)

    for path in FILES:
        language = path.parent.name.removesuffix(".lproj")
        info = INSTALLER_ROOT / f"{language}.lproj" / "InfoPlist.strings"
        if not info.exists():
            failed = True
            print(f"{language}: installer InfoPlist.strings is missing", file=sys.stderr)
            continue
        keys = keys_of(info)
        for key in ("CFBundleDisplayName", "CFBundleName"):
            if key not in keys:
                failed = True
                print(f"{language}: installer InfoPlist.strings has no {key}", file=sys.stderr)

    if failed:
        return 1
    print(f"{len(FILES)} languages, {len(reference)} keys each, installer names localized")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
