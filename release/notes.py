#!/usr/bin/env python3
"""Print a version's changelog section (for the GitHub release's notes).

Usage: python3 release/notes.py --version X.Y.Z
"""
import argparse
import sys

import common


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    args = parser.parse_args(argv)
    try:
        print(common.section_text(common.CHANGELOG.read_text(encoding="utf-8"), args.version))
    except common.ReleaseError as e:
        print(f"notes: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
