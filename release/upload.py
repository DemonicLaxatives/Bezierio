#!/usr/bin/env python3
"""Upload a release zip to the mod portal (FACTORIO_API_KEY with the
"ModPortal: Upload Mods" permission). Run by the release workflow after
validate.py; by hand only if that failed halfway.

Usage: python3 release/upload.py dist/Bezierio_X.Y.Z.zip
"""
import argparse
import sys

import common
import portal


def main(argv=None, client=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("zip")
    args = parser.parse_args(argv)
    mod = common.read_info()["name"]
    try:
        (client or portal.Portal()).upload_release(mod, args.zip)
    except portal.PortalError as e:
        print(f"upload: {e}", file=sys.stderr)
        return 1
    print(f"Uploaded {args.zip} for {mod}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
