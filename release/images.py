#!/usr/bin/env python3
"""Keep the mod portal's images the same as mod-portal/images/ (the one source
of truth), in the order of order.txt. Run by the portal workflow (a portal-*
tag), or by hand with FACTORIO_API_KEY ("ModPortal: Edit Mods").

- An image is uploaded when it's new, or its file changed (its SHA1 differs from
  the one recorded in mod-portal-ids.json), or the portal no longer has it.
- The page's image list is set to order.txt's order (images left out are taken
  off the page), unless it's that already.
- mod-portal-ids.json is rewritten: per image, its file's SHA1 and its id, url
  and thumbnail on the portal (detail.py links the description's images to them).

Usage: python3 release/images.py [--dry-run]
"""
import argparse
import hashlib
import json
import pathlib
import sys

import common
import portal

IMAGES = common.REPO / "mod-portal" / "images"
ORDER = IMAGES / "order.txt"
IDS = IMAGES / "mod-portal-ids.json"


def sha1(path):
    return hashlib.sha1(pathlib.Path(path).read_bytes()).hexdigest()


def read_order(text):
    """Image file names, in order (blank lines and # comments skipped)."""
    return [l.strip() for l in text.splitlines() if l.strip() and not l.strip().startswith("#")]


def read_ids(path=IDS):
    """{name: entry} from mod-portal-ids.json (entries without an id are ignored)."""
    if not pathlib.Path(path).exists():
        return {}
    out = {}
    for entry in json.loads(pathlib.Path(path).read_text(encoding="utf-8")):
        if entry.get("name_in_repo") and entry.get("id_on_mod_portal"):
            out[entry["name_in_repo"]] = entry
    return out


def plan(order, files, recorded, on_portal):
    """What to do: (uploads: [name], ids_after: {name: id or None}).
    files: {name: sha1}; recorded: {name: entry}; on_portal: {id: image}."""
    uploads, ids = [], {}
    for name in order:
        entry = recorded.get(name)
        same_file = entry is not None and entry.get("sha1") == files[name]
        if same_file and entry["id_on_mod_portal"] in on_portal:
            ids[name] = entry["id_on_mod_portal"]
        elif files[name] in on_portal:
            ids[name] = files[name]  # (the portal's id is the image's SHA1)
        else:
            uploads.append(name)
            ids[name] = None
    return uploads, ids


def sync(client, mod, images_dir=IMAGES, dry_run=False):
    """Bring the portal in line; (changed: bool, entries: [ids.json entry])."""
    images_dir = pathlib.Path(images_dir)
    order = read_order((images_dir / "order.txt").read_text(encoding="utf-8"))
    missing = [n for n in order if not (images_dir / n).exists()]
    if missing:
        raise common.ReleaseError(f"order.txt names images that aren't there: {missing}")
    files = {name: sha1(images_dir / name) for name in order}
    page = client.mod_info(mod).get("images", [])
    on_portal = {img["id"]: img for img in page}
    portal_order = [img["id"] for img in page]
    uploads, ids = plan(order, files, read_ids(images_dir / "mod-portal-ids.json"), on_portal)
    for name in uploads:
        print(f"upload {name}")
        if dry_run:
            continue
        try:
            image = client.add_image(mod, images_dir / name)
        except portal.PortalError as e:
            # Uploaded before but not on the page (an earlier run stopped in
            # between): the portal keeps it under its SHA1, so use that.
            if "already exists" not in (e.message or ""):
                raise
            print("  (the portal has it already)")
            image = {"id": files[name]}
        on_portal.setdefault(image["id"], image)
        ids[name] = image["id"]
    wanted = [ids[n] for n in order]
    changed = bool(uploads) or portal_order != wanted
    if changed:
        print("set the page's images: " + ", ".join(order))
        if not dry_run:
            for image in client.set_images(mod, wanted).get("images", []):
                on_portal[image["id"]] = image
    entries = []
    for name in order:
        image = on_portal.get(ids[name] or "", {})
        entries.append({
            "name_in_repo": name, "sha1": files[name], "id_on_mod_portal": ids[name],
            "url": image.get("url"), "thumbnail": image.get("thumbnail"),
        })
    return changed, entries


def main(argv=None, client=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true", help="say what would change, change nothing")
    args = parser.parse_args(argv)
    mod = common.read_info()["name"]
    try:
        changed, entries = sync(client or portal.Portal(), mod, dry_run=args.dry_run)
    except (portal.PortalError, common.ReleaseError) as e:
        print(f"images: {e}", file=sys.stderr)
        return 1
    if not changed:
        print("images: the portal has them already")
    if not args.dry_run:
        IDS.write_text(json.dumps(entries, indent=4) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
