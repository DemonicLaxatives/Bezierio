#!/usr/bin/env python3
"""Check a release before it goes out; prints every problem, exit 1 if any.

- the tag (vX.Y.Z) matches info.json and the changelog's first section;
- changelog.txt is in Factorio's format (no 0.0.0 placeholder left);
- no locale comment is still marked [unreviewed];
- with --zip: it holds one Bezierio_X.Y.Z/ folder with info.json, no test or
  repository files, and scripts/debug.lua has `lib.debug = false`.

Usage: python3 release/validate.py --tag vX.Y.Z [--zip dist/Bezierio_X.Y.Z.zip]
"""
import argparse
import json
import re
import sys
import zipfile

import common

#: Folders and files that never go into the zip (see .gitattributes).
NOT_SHIPPED = ("tests/", "docs/", "mod-portal/", "release/", ".github/", ".vscode/", "python_scripts/", "CLAUDE.md")


def repo_problems(tag, info, changelog_text, locale_text):
    problems = []
    m = re.fullmatch(r"v(\d+\.\d+\.\d+)", tag or "")
    if not m:
        return [f"tag {tag!r} isn't vX.Y.Z"]
    version = m.group(1)
    if info.get("version") != version:
        problems.append(f"info.json has version {info.get('version')}, the tag {version} (run release/bump.py)")
    latest = common.latest_version(changelog_text)
    if latest != version:
        problems.append(f"changelog.txt starts with version {latest}, the tag {version} (run release/bump.py)")
    problems += ["changelog.txt " + p for p in common.changelog_problems(changelog_text)]
    unreviewed = common.unreviewed_lines(locale_text)
    if unreviewed:
        shown = ", ".join(str(n) for n in unreviewed[:10]) + (", ..." if len(unreviewed) > 10 else "")
        problems.append(f"locale/en/Bezierio.cfg: {len(unreviewed)} comments still {common.REVIEW_MARK} (lines {shown})")
    return problems


def zip_problems(zip_path, info):
    folder = f"{info.get('name')}_{info.get('version')}/"
    problems = []
    with zipfile.ZipFile(zip_path) as zf:
        names = zf.namelist()
        outside = [n for n in names if not n.startswith(folder)]
        if outside:
            problems.append(f"zip: entries outside {folder}: {outside[:5]}")
        if folder + "info.json" not in names:
            problems.append(f"zip: no {folder}info.json")
        else:
            inner = json.loads(zf.read(folder + "info.json"))
            if inner.get("version") != info.get("version"):
                problems.append(f"zip: info.json has version {inner.get('version')}")
        shipped = [n[len(folder):] for n in names if n.startswith(folder)]
        stray = [n for n in shipped if n.startswith(NOT_SHIPPED)]
        if stray:
            problems.append(f"zip: holds files that don't ship: {stray[:5]}")
        debug = folder + common.DEBUG_LUA
        if debug in names and not re.search(r"^lib\.debug = false$", zf.read(debug).decode("utf-8"), flags=re.M):
            problems.append(f"zip: {common.DEBUG_LUA} doesn't have lib.debug = false")
    return problems


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--zip")
    args = parser.parse_args(argv)
    info = common.read_info()
    problems = repo_problems(args.tag, info, common.CHANGELOG.read_text(encoding="utf-8"),
                             common.LOCALE.read_text(encoding="utf-8"))
    if args.zip:
        problems += zip_problems(args.zip, info)
    for p in problems:
        print(p)
    print(f"{len(problems)} problems")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
