#!/usr/bin/env python3
"""Fails when a Localizable.strings file is missing keys the others have."""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILES = sorted((ROOT / "Resources" / "strings").glob("*.lproj/Localizable.strings"))
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

    if failed:
        return 1
    print(f"{len(FILES)} languages, {len(reference)} keys each")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
