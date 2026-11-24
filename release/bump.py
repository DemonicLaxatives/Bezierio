#!/usr/bin/env python3
"""Set the version for a release, in the repository: info.json gets it, and the
changelog's first section (the 0.0.0 placeholder, or already that version) gets
it with today's date. Then commit, and tag vX.Y.Z.

Usage: python3 release/bump.py --version X.Y.Z [--date DD.MM.YYYY]
"""
import argparse
import datetime
import sys

import common


def bump(version, date, info_path=common.INFO, changelog_path=common.CHANGELOG):
    """Write the new version; ReleaseError (nothing written) if the changelog isn't
    ready for it."""
    common.parse_version(version)
    text = changelog_path.read_text(encoding="utf-8")
    new_text = common.set_latest(text, version, date)
    problems = common.changelog_problems(new_text)
    if problems:
        raise common.ReleaseError("changelog.txt:\n  " + "\n  ".join(problems))
    info = common.read_info(info_path)
    info["version"] = version
    common.write_info(info, info_path)
    changelog_path.write_text(new_text, encoding="utf-8")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--version", required=True)
    parser.add_argument("--date", default=datetime.date.today().strftime("%d.%m.%Y"))
    args = parser.parse_args(argv)
    try:
        bump(args.version, args.date)
    except common.ReleaseError as e:
        print(f"bump: {e}", file=sys.stderr)
        return 1
    print(f"Version {args.version} ({args.date}) in info.json and changelog.txt: commit, then tag v{args.version}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
