#!/usr/bin/env python3
"""Every "section.key" written out in full in the Lua code exists in the English
locale. Keys built at runtime ("tooltip." .. field.name) can't be checked here.

Usage: python3 tests/lint/locale_keys.py   (exit 1 when a key is missing)
"""
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
LOCALE = REPO / "locale" / "en" / "Bezierio.cfg"
SOURCES = ["scripts", "prototypes", "control.lua", "data.lua", "data-final-fixes.lua", "settings.lua"]


def parse_locale(text):
    """{section: {key, ...}} from a Factorio .cfg (comments start with ; or #)."""
    keys, section = {}, ""
    for line in text.splitlines():
        line = line.strip()
        if not line or line[0] in ";#":
            continue
        m = re.fullmatch(r"\[(.+)\]", line)
        if m:
            section = m.group(1)
            keys.setdefault(section, set())
        elif "=" in line:
            keys.setdefault(section, set()).add(line.split("=", 1)[0])
    return keys


def referenced(text, sections):
    """The full keys of known sections written in a Lua source (not prefixes that
    are joined with `..` to more of the key)."""
    for m in re.finditer(r'"([a-z][a-z0-9-]*)\.([a-z0-9][a-z0-9_-]*)"(?!\s*\.\.)', text):
        section, key = m.groups()
        if section in sections:
            yield section, key, text.count("\n", 0, m.start()) + 1


def missing_keys(locale_text, sources):
    """[(file, line, "section.key")] for keys the locale doesn't have."""
    keys = parse_locale(locale_text)
    out = []
    for name, text in sources:
        for section, key, line in referenced(text, keys):
            if key not in keys[section]:
                out.append((name, line, f"{section}.{key}"))
    return out


def lua_files():
    for entry in SOURCES:
        path = REPO / entry
        files = sorted(path.rglob("*.lua")) if path.is_dir() else [path] if path.exists() else []
        for f in files:
            yield str(f.relative_to(REPO)), f.read_text(encoding="utf-8")


def main():
    problems = missing_keys(LOCALE.read_text(encoding="utf-8"), lua_files())
    for name, line, key in problems:
        print(f"{name}:{line}: {key} is not in locale/en/Bezierio.cfg")
    print(f"{len(problems)} missing locale keys")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
