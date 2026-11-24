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
