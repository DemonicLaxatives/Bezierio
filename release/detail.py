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

Videos can't be uploaded to the portal: links to videos in mod-portal/images/
(.webm, .mp4, ...) are swapped for the file in the GitHub repository instead,
at the commit being synced (raw.githubusercontent.com, so the link keeps
working when the video changes later). That commit must be on GitHub and hold
the video: in the portal workflow it's the tag's (GITHUB_SHA); by hand, HEAD,
which must be on a pushed branch, or --ref.

Usage: python3 release/detail.py [--all] [--dry-run] [--ref COMMIT]
"""
import argparse
import os
import re
import subprocess
import sys

import common
import images
import portal

PAGE = common.REPO / "mod-portal"
FIELDS = {"summary": "summary.txt", "description": "description.md", "faq": "faq.md"}
LIMITS = {"summary": 500}


IMAGE_TYPES = ("png", "jpg", "jpeg", "gif", "webp")
#: Where the videos are, in the repository.
VIDEO_DIR = "mod-portal/images"


def portal_links(text, urls, video_url=None):
    """The text with links to repository images (any URL or path ending in
    mod-portal/images/NAME, or images/NAME) swapped for the portal's URLs, and
    links to videos there for `video_url(NAME)`. ReleaseError for an image the
    portal doesn't have, or a video with no `video_url`."""
    def swap(m):
        name = m.group("name")
        if common.is_video(name):
            if not video_url:
                raise common.ReleaseError(f"the description links the video {name}, but there's no repository to link it in")
            return video_url(name)
        if not urls.get(name):
            raise common.ReleaseError(f"the description links {name}, which isn't on the portal (run images.py)")
        return urls[name]
    types = "|".join(IMAGE_TYPES + common.VIDEO_TYPES)
    pattern = r"(?:https?://[^\s()\"']*?/)?(?:mod-portal/)?images/(?P<name>[\w.-]+\.(?:" + types + r"))\b"
    return re.sub(pattern, swap, text, flags=re.IGNORECASE)


def git(*args, run=subprocess.run):
    """A git command's output in the repository (stripped), or None if it fails."""
    done = run(["git", *args], cwd=common.REPO, capture_output=True, text=True)
    return done.stdout.strip() if done.returncode == 0 else None


def github_repository(remote_url):
    """OWNER/NAME from a GitHub remote URL (ssh or https), or None."""
    m = re.match(r"^(?:git@github\.com:|ssh://git@github\.com/|https://github\.com/)([\w.-]+/[\w.-]+?)(?:\.git)?/?$", remote_url or "")
    return m.group(1) if m else None


def raw_url(repository, ref, name):
    return f"https://raw.githubusercontent.com/{repository}/{ref}/{VIDEO_DIR}/{name}"


def video_linker(ref=None, env=None, git=git):
    """`video_url(NAME)` for portal_links: the video at the synced commit on
    GitHub. The repository is GITHUB_REPOSITORY or origin's; the commit `ref`,
    else GITHUB_SHA (the workflow's tag), else HEAD, which must then be on a
    pushed branch. Each video is checked to be in that commit. Worked out at the
    first video, so a description without one needs none of it (ReleaseError)."""
    env = os.environ if env is None else env
    where = {}

    def resolve():
        repository = env.get("GITHUB_REPOSITORY") or github_repository(git("remote", "get-url", "origin"))
        if not repository:
            raise common.ReleaseError("videos are linked on GitHub, but origin isn't a GitHub repository")
        commit = ref or env.get("GITHUB_SHA")
        if commit:
            commit = git("rev-parse", "--verify", commit + "^{commit}") or commit
        else:
            commit = git("rev-parse", "HEAD")
            if not commit or not git("branch", "-r", "--contains", commit):
                raise common.ReleaseError("videos are linked at HEAD on GitHub, which isn't pushed: push it, or give --ref")
        where["repository"], where["commit"] = repository, commit

    def video_url(name):
        if not where:
            resolve()
        commit = where["commit"]
        if git("cat-file", "-e", f"{commit}:{VIDEO_DIR}/{name}") is None:
            raise common.ReleaseError(f"the description links the video {name}, which isn't in {commit[:12]} (commit it)")
        return raw_url(where["repository"], commit, name)
    return video_url


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


def build(fields, page_dir=PAGE, urls=None, video_url=None):
    """{field: text to send}, with the description's image and video links swapped."""
    data = {}
    for field in fields:
        text = (page_dir / FIELDS[field]).read_text(encoding="utf-8").strip("\n")
        if field == "description":
            text = portal_links(text, urls or {}, video_url)
        limit = LIMITS.get(field)
        if limit and len(text) > limit:
            raise common.ReleaseError(f"{FIELDS[field]}: {len(text)} characters, the portal takes {limit}")
        data[field] = text
    return data


def main(argv=None, client=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--all", action="store_true", help="send every field")
    parser.add_argument("--dry-run", action="store_true", help="print what would be sent")
    parser.add_argument("--ref", help="the commit (or tag, branch) to link videos at, on GitHub")
    args = parser.parse_args(argv)
    mod = common.read_info()["name"]
    try:
        client = client or portal.Portal()
        urls = {name: e.get("url") for name, e in images.read_ids().items()}
        local = build(list(FIELDS), urls=urls, video_url=video_linker(args.ref))
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
