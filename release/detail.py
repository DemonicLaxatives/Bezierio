#!/usr/bin/env python3
"""Keep the mod portal page's texts the same as mod-portal/ (the one source of
truth): summary.txt, description.md, faq.md. Run by the portal workflow after
images.py, or by hand with FACTORIO_API_KEY ("ModPortal: Edit Mods").

A field is sent when it differs from what the page shows now (read from the
portal's public page data), so a sync that failed halfway is caught up by the
next one; the FAQ isn't in that data, so it's always sent (that changes nothing
when it's the same). --all sends every field. Links to images in
mod-portal/images/ (relative, images/NAME, so GitHub shows them on any branch;
full GitHub URLs work too) are swapped for the portal's own image URLs from
mod-portal-ids.json; the repository keeps its links.

Usage: python3 release/detail.py [--all] [--dry-run]
"""
import argparse
import re
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


def same_text(a, b):
    """Equal as the page shows them (line endings, surrounding blank lines aside)."""
    def norm(t):
        return (t or "").replace("\r\n", "\n").strip()
    return norm(a) == norm(b)


def fields_to_send(local, live, everything=False):
    """Which fields go: those that differ from the live page (fields it doesn't
    show, like the FAQ, always)."""
    if everything:
        return list(local)
    return [f for f, text in local.items() if f not in live or not same_text(text, live[f])]


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
    parser.add_argument("--dry-run", action="store_true", help="print what would be sent")
    args = parser.parse_args(argv)
    mod = common.read_info()["name"]
    try:
        client = client or portal.Portal()
        urls = {name: e.get("url") for name, e in images.read_ids().items()}
        local = build(list(FIELDS), urls=urls)
        live = {f: v for f, v in client.mod_info(mod).items() if f in FIELDS}
        fields = fields_to_send(local, live, args.all)
        if not fields:
            print("details: the page has them already")
            return 0
        data = {f: local[f] for f in fields}
        if args.dry_run:
            for field, text in data.items():
                print(f"--- {field} ---\n{text}\n")
            return 0
        client.edit_details(mod, data)
    except (portal.PortalError, common.ReleaseError) as e:
        print(f"details: {e}", file=sys.stderr)
        return 1
    print("details: sent " + ", ".join(fields))
    return 0


if __name__ == "__main__":
    sys.exit(main())
