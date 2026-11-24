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


def test_only_changed_fields_go():
    assert detail.fields_to_send({"faq.md", "images/x.png"}, False, False) == ["faq"]
    assert detail.fields_to_send({"faq.md"}, True, False) == ["faq", "description"]
    assert detail.fields_to_send(set(), False, True) == ["summary", "description", "faq"]


def test_build_reads_the_files_and_checks_lengths(tmp_path):
    (tmp_path / "summary.txt").write_text("Short.\n")
    (tmp_path / "description.md").write_text("![b](images/belt-bus.png)\n")
    assert detail.build(["summary", "description"], tmp_path, URLS) == {"summary": "Short.", "description": f"![b]({URLS['belt-bus.png']})"}
    (tmp_path / "summary.txt").write_text("x" * 501)
    with pytest.raises(common.ReleaseError, match="500"):
        detail.build(["summary"], tmp_path, URLS)


def test_changes_since_the_previous_portal_tag(tmp_path):
    import subprocess

    def git(*args):
        subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@example.invalid", *args], cwd=tmp_path, check=True, capture_output=True)

    (tmp_path / "mod-portal").mkdir()
    (tmp_path / "mod-portal" / "summary.txt").write_text("a")
    (tmp_path / "mod-portal" / "faq.md").write_text("a")
    git("init", "-q")
    git("add", ".")
    git("commit", "-q", "-m", "1")
    git("tag", "portal-1")
    (tmp_path / "mod-portal" / "faq.md").write_text("b")
    git("commit", "-qam", "2")
    git("tag", "portal-2")
    assert detail.previous_tag(tmp_path) == "portal-1"
    assert detail.changed_files("portal-1", tmp_path) == {"faq.md"}
