#!/usr/bin/env python3
"""Keep the mod portal page's texts the same as mod-portal/ (the one source of
truth): summary.txt, description.md, faq.md. Run by the portal workflow after
images.py, or by hand with FACTORIO_API_KEY ("ModPortal: Edit Mods").

Only fields whose file changed since the previous portal-* tag are sent (all of
them when there's no earlier tag, or with --all). Links to images in
mod-portal/images/ (relative, images/NAME, so GitHub shows them on any branch;
full GitHub URLs work too) are swapped
for the portal's own image URLs from mod-portal-ids.json; the repository keeps
its links. When an image's portal URL changed, the description goes again.

Usage: python3 release/detail.py [--all] [--since TAG] [--images-changed] [--dry-run]
"""
import argparse
import re
import subprocess
import sys

import common
import images
import portal

PAGE = common.REPO / "mod-portal"
FIELDS = {"summary": "summary.txt", "description": "description.md", "faq": "faq.md"}
LIMITS = {"summary": 500}


def portal_links(text, urls):
    """The text with links to repository images (any URL or path ending in
    mod-portal/images/NAME, or images/NAME) swapped for the portal's URLs.
    ReleaseError for an image the portal doesn't have."""
    def swap(m):
        name = m.group("name")
        if not urls.get(name):
            raise common.ReleaseError(f"the description links {name}, which isn't on the portal (run images.py)")
        return urls[name]
    pattern = r"(?:https?://[^\s()\"']*?/)?(?:mod-portal/)?images/(?P<name>[\w.-]+\.(?:png|jpe?g|gif|webp))"
    return re.sub(pattern, swap, text)


def previous_tag(repo=common.REPO):
    """The latest portal-* tag before HEAD, or None."""
    result = subprocess.run(["git", "describe", "--tags", "--abbrev=0", "--match", "portal-*", "HEAD^"],
                            cwd=repo, capture_output=True, text=True)
    if result.returncode != 0:
        return None
    return result.stdout.strip() or None


def changed_files(since, repo=common.REPO):
    """mod-portal/ files changed between `since` and HEAD."""
    out = subprocess.run(["git", "diff", "--name-only", since, "HEAD", "--", "mod-portal/"],
                         cwd=repo, capture_output=True, text=True, check=True).stdout
    return {line.split("/", 1)[1] for line in out.splitlines() if line.startswith("mod-portal/")}


def fields_to_send(changed, images_changed, everything):
    """Which page fields go: those whose file changed (all, with everything)."""
    if everything:
        return list(FIELDS)
    out = [field for field, name in FIELDS.items() if name in changed]
    if images_changed and "description" not in out:
        out.append("description")
    return out


def build(fields, page_dir=PAGE, urls=None):
    """{field: text to send}, with the description's image links swapped."""
    data = {}
    for field in fields:
        text = (page_dir / FIELDS[field]).read_text(encoding="utf-8").strip("\n")
        if field == "description":
            text = portal_links(text, urls or {})
        limit = LIMITS.get(field)
        if limit and len(text) > limit:
            raise common.ReleaseError(f"{FIELDS[field]}: {len(text)} characters, the portal takes {limit}")
        data[field] = text
    return data


def main(argv=None, client=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--all", action="store_true", help="send every field")
    parser.add_argument("--since", help="compare with this tag (default: the previous portal-* tag)")
    parser.add_argument("--images-changed", action="store_true", help="an image's portal URL changed")
    parser.add_argument("--dry-run", action="store_true", help="print what would be sent")
    args = parser.parse_args(argv)
    since = args.since or previous_tag()
    everything = args.all or since is None
    try:
        fields = fields_to_send(set() if everything else changed_files(since), args.images_changed, everything)
        if not fields:
            print(f"details: nothing changed since {since}")
            return 0
        urls = {name: e.get("url") for name, e in images.read_ids().items()}
        data = build(fields, urls=urls)
        if args.dry_run:
            for field, text in data.items():
                print(f"--- {field} ---\n{text}\n")
            return 0
        mod = common.read_info()["name"]
        (client or portal.Portal()).edit_details(mod, data)
    except (portal.PortalError, common.ReleaseError, subprocess.CalledProcessError) as e:
        print(f"details: {e}", file=sys.stderr)
        return 1
    print("details: sent " + ", ".join(fields))
    return 0


if __name__ == "__main__":
    sys.exit(main())
