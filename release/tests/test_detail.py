import pytest

import common
import detail

URLS = {"belt-bus.png": "https://assets-mod.factorio.com/assets/abc.png"}


def test_repository_image_links_become_portal_links():
    text = ('![Bus](https://raw.githubusercontent.com/X/Bezierio/refs/heads/main/mod-portal/images/belt-bus.png "A bus")\n'
            "![Bus](images/belt-bus.png)\n[elsewhere](https://example.com/page)")
    out = detail.portal_links(text, URLS)
    assert out.count(URLS["belt-bus.png"]) == 2
    assert '"A bus"' in out and "https://example.com/page" in out and "githubusercontent" not in out


def test_an_image_not_on_the_portal_stops_it():
    with pytest.raises(common.ReleaseError, match="railway.png"):
        detail.portal_links("![x](mod-portal/images/railway.png)", URLS)


def test_fields_that_differ_from_the_live_page_go():
    local = {"summary": "S", "description": "D2", "faq": "F"}
    live = {"summary": "S\r\n", "description": "D1"}
    assert detail.fields_to_send(local, live) == ["description", "faq"]
    assert detail.fields_to_send(local, {"summary": "S", "description": "D2", "faq": "F"}) == []
    assert detail.fields_to_send(local, live, everything=True) == ["summary", "description", "faq"]


def test_build_reads_the_files_and_checks_lengths(tmp_path):
    (tmp_path / "summary.txt").write_text("Short.\n")
    (tmp_path / "description.md").write_text("![b](images/belt-bus.png)\n")
    assert detail.build(["summary", "description"], tmp_path, URLS) == {"summary": "Short.", "description": f"![b]({URLS['belt-bus.png']})"}
    (tmp_path / "summary.txt").write_text("x" * 501)
    with pytest.raises(common.ReleaseError, match="500"):
        detail.build(["summary"], tmp_path, URLS)


# Videos: the portal takes none, so they're linked in the GitHub repository, at
# the commit being synced.

class FakeGit:
    """git as the video links ask it: origin, HEAD, pushed branches, files in commits."""

    def __init__(self, origin="git@github.com:Owner/Bezierio.git", head="c0ffee" * 6 + "abcd", pushed=True, files=("demo.webm",)):
        self.origin, self.head, self.pushed, self.files, self.calls = origin, head, pushed, set(files), []

    def __call__(self, *args):
        self.calls.append(args)
        if args[:2] == ("remote", "get-url"):
            return self.origin
        if args == ("rev-parse", "HEAD"):
            return self.head
        if args[:2] == ("rev-parse", "--verify"):
            return self.head if args[2].startswith(("portal-", self.head)) else None
        if args[:2] == ("branch", "-r"):
            return "origin/main" if self.pushed else ""
        if args[0] == "cat-file":
            name = args[2].split(":", 1)[1].rsplit("/", 1)[-1]
            return "" if name in self.files else None
        raise AssertionError(args)


def test_a_video_is_linked_in_the_repository_at_the_commit():
    git = FakeGit()
    video_url = detail.video_linker(env={}, git=git)
    text = '![A demonstration](images/demo.webm "Demo")\n![Bus](images/belt-bus.png)'
    out = detail.portal_links(text, URLS, video_url)
    assert f"https://raw.githubusercontent.com/Owner/Bezierio/{git.head}/mod-portal/images/demo.webm" in out
    assert '"Demo"' in out and URLS["belt-bus.png"] in out


def test_in_the_workflow_the_tag_s_commit_and_repository():
    git = FakeGit(origin=None)
    video_url = detail.video_linker(env={"GITHUB_REPOSITORY": "Owner/Bezierio", "GITHUB_SHA": git.head}, git=git)
    assert video_url("demo.webm") == f"https://raw.githubusercontent.com/Owner/Bezierio/{git.head}/mod-portal/images/demo.webm"
    assert ("branch", "-r", "--contains", git.head) not in git.calls  # (the tag was pushed)


def test_a_ref_is_resolved_to_its_commit():
    git = FakeGit(pushed=False)
    assert git.head in detail.video_linker(ref="portal-2026-11-28", env={}, git=git)("demo.webm")


def test_without_a_video_nothing_is_asked():
    git = FakeGit(pushed=False, origin="somewhere else")
    assert detail.portal_links("![Bus](images/belt-bus.png)", URLS, detail.video_linker(env={}, git=git)) == f"![Bus]({URLS['belt-bus.png']})"
    assert git.calls == []


@pytest.mark.parametrize("git, message", [
    (FakeGit(pushed=False), "isn't pushed"),
    (FakeGit(files=()), "isn't in"),
    (FakeGit(origin="https://gitlab.com/x/y.git"), "isn't a GitHub repository"),
])
def test_a_video_link_that_would_be_dead_stops_it(git, message):
    with pytest.raises(common.ReleaseError, match=message):
        detail.portal_links("![v](images/demo.webm)", URLS, detail.video_linker(env={}, git=git))


def test_github_remotes():
    assert detail.github_repository("git@github.com:Owner/Bezierio.git") == "Owner/Bezierio"
    assert detail.github_repository("https://github.com/Owner/Bezierio") == "Owner/Bezierio"
    assert detail.github_repository("ssh://git@github.com/Owner/Bezierio.git") == "Owner/Bezierio"
    assert detail.github_repository("https://gitlab.com/Owner/Bezierio.git") is None
