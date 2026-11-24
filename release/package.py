#!/usr/bin/env python3
"""Build the release zip, Bezierio_X.Y.Z.zip, holding a Bezierio_X.Y.Z/ folder.

From a commit (default HEAD) with `git archive`, so what goes in is what's
committed, minus the paths marked `export-ignore` in .gitattributes (tests,
docs, the mod portal page, the release scripts, ...): local and CI zips are the
same. In the zip, not the repository, scripts/debug.lua gets `lib.debug = false`.
Entries are sorted and dated 1980-01-01, so the same commit gives the same bytes.

Usage: python3 release/package.py [--ref HEAD] [--out dist]   (prints the zip's path)
"""
import argparse
import io
import json
import pathlib
import re
import subprocess
import sys
import tarfile
import zipfile

import common

FIXED_TIME = (1980, 1, 1, 0, 0, 0)


def release_debug_lua(text):
    """debug.lua with debug output off; ReleaseError if the switch isn't there."""
    new, count = re.subn(r"^lib\.debug = true$", "lib.debug = false", text, flags=re.M)
    if count == 0 and not re.search(r"^lib\.debug = false$", text, flags=re.M):
        raise common.ReleaseError(f"{common.DEBUG_LUA}: no `lib.debug = true/false` line to switch off")
    return new


def files_at(ref, repo=common.REPO):
    """{path: bytes} of the files `git archive` exports at `ref`."""
    tar_bytes = subprocess.run(["git", "archive", "--worktree-attributes", "--format=tar", ref], cwd=repo, check=True, capture_output=True).stdout
    out = {}
    with tarfile.open(fileobj=io.BytesIO(tar_bytes)) as tar:
        for member in tar.getmembers():
            if member.isfile():
                out[member.name] = tar.extractfile(member).read()
    return out


def build_zip(files, name, version):
    """The zip's bytes: every file under `name_version/`, debug output off."""
    folder = f"{name}_{version}"
    files = dict(files)
    if common.DEBUG_LUA in files:
        files[common.DEBUG_LUA] = release_debug_lua(files[common.DEBUG_LUA].decode("utf-8")).encode("utf-8")
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(files):
            info = zipfile.ZipInfo(f"{folder}/{path}", FIXED_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            zf.writestr(info, files[path])
    return buffer.getvalue()


def package(ref="HEAD", out=common.REPO / "dist", repo=common.REPO):
    """Write the zip for `ref`; its path."""
    files = files_at(ref, repo)
    if "info.json" not in files:
        raise common.ReleaseError(f"no info.json at {ref}")
    info = json.loads(files["info.json"])
    path = pathlib.Path(out) / f"{info['name']}_{info['version']}.zip"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(build_zip(files, info["name"], info["version"]))
    return path


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ref", default="HEAD")
    parser.add_argument("--out", default=str(common.REPO / "dist"))
    args = parser.parse_args(argv)
    try:
        print(package(args.ref, args.out))
    except (common.ReleaseError, subprocess.CalledProcessError) as e:
        print(f"package: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
