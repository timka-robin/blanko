#!/usr/bin/env python3
"""Adds localized Services menu titles to a built Info.plist.

Titles come from the same Localizable.strings files the app uses, so the
Services entries never drift away from the in-app menu.

    tools/localize-plist.py <built Info.plist> <repo root>
"""

import pathlib
import plistlib
import re
import sys

SERVICE_KEYS = ["action_text", "action_word", "action_excel"]
PAIR_PATTERN = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', re.MULTILINE)


def read_strings(path: pathlib.Path) -> dict[str, str]:
    return {key: value for key, value in PAIR_PATTERN.findall(path.read_text(encoding="utf-8"))}


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2

    plist_path = pathlib.Path(sys.argv[1])
    root = pathlib.Path(sys.argv[2])

    translations: dict[str, dict[str, str]] = {}
    for lproj in sorted((root / "Resources" / "strings").glob("*.lproj")):
        language = lproj.name.removesuffix(".lproj")
        translations[language] = read_strings(lproj / "Localizable.strings")

    if "en" not in translations:
        print("en localization is required", file=sys.stderr)
        return 1

    data = plistlib.loads(plist_path.read_bytes())
    services = data.get("NSServices", [])
    if len(services) != len(SERVICE_KEYS):
        print(f"expected {len(SERVICE_KEYS)} services, found {len(services)}", file=sys.stderr)
        return 1

    for service, key in zip(services, SERVICE_KEYS):
        menu = dict(service.get("NSMenuItem", {}))
        menu["default"] = translations["en"][key]
        for language, strings in translations.items():
            menu[language] = strings[key]
        service["NSMenuItem"] = menu

    plist_path.write_bytes(plistlib.dumps(data))
    print(f"services localized into {len(translations)} languages")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
