import hashlib
import json

import pytest

import common
import images


class FakePortal:
    """A page with images; uploads give the file's SHA1 as id, like the portal."""

    def __init__(self, page=None):
        self.page, self.calls = list(page or []), []

    def mod_info(self, mod):
        return {"images": [dict(i) for i in self.page]}

    def add_image(self, mod, path):
        image_id = hashlib.sha1(path.read_bytes()).hexdigest()
        self.calls.append(("add", path.name))
        image = {"id": image_id, "url": f"https://assets/{image_id}.png", "thumbnail": f"https://assets/t/{image_id}.png"}
        self.page.append(image)
        return image

    def set_images(self, mod, ids):
        self.calls.append(("set", list(ids)))
        known = {i["id"]: i for i in self.page}
        self.page = [known[i] for i in ids]
        return {"success": True, "images": self.page}


def folder(tmp_path, files, order):
    for name, data in files.items():
        (tmp_path / name).write_bytes(data)
    (tmp_path / "order.txt").write_text("\n".join(order) + "\n")
    return tmp_path


def sha(data):
    return hashlib.sha1(data).hexdigest()


def test_new_images_are_uploaded_and_ordered(tmp_path):
    d = folder(tmp_path, {"a.png": b"A", "b.png": b"B"}, ["b.png", "a.png"])
    client = FakePortal()
    changed, entries = images.sync(client, "Bezierio", d)
    assert changed and [c[0] for c in client.calls] == ["add", "add", "set"]
    assert client.calls[-1] == ("set", [sha(b"B"), sha(b"A")])
    assert [e["name_in_repo"] for e in entries] == ["b.png", "a.png"]
    assert entries[0]["url"] == f"https://assets/{sha(b'B')}.png" and entries[0]["sha1"] == sha(b"B")


def test_nothing_to_do_when_the_portal_has_them(tmp_path):
    d = folder(tmp_path, {"a.png": b"A"}, ["a.png"])
    client = FakePortal([{"id": sha(b"A"), "url": "u", "thumbnail": "t"}])
    changed, entries = images.sync(client, "Bezierio", d)
    assert not changed and client.calls == []
    assert entries[0]["url"] == "u"


def test_a_changed_file_is_uploaded_again_and_the_old_one_dropped(tmp_path):
    d = folder(tmp_path, {"a.png": b"A2"}, ["a.png"])
    (d / "mod-portal-ids.json").write_text(json.dumps([{"name_in_repo": "a.png", "sha1": sha(b"A"), "id_on_mod_portal": sha(b"A")}]))
    client = FakePortal([{"id": sha(b"A"), "url": "old", "thumbnail": "t"}])
    changed, entries = images.sync(client, "Bezierio", d)
    assert changed and client.calls == [("add", "a.png"), ("set", [sha(b"A2")])]
    assert [i["id"] for i in client.page] == [sha(b"A2")]


def test_reordering_only_sets_the_order(tmp_path):
    d = folder(tmp_path, {"a.png": b"A", "b.png": b"B"}, ["b.png", "a.png"])
    client = FakePortal([{"id": sha(b"A"), "url": "ua", "thumbnail": ""}, {"id": sha(b"B"), "url": "ub", "thumbnail": ""}])
    changed, _ = images.sync(client, "Bezierio", d)
    assert changed and client.calls == [("set", [sha(b"B"), sha(b"A")])]


def test_dry_run_changes_nothing(tmp_path):
    d = folder(tmp_path, {"a.png": b"A"}, ["a.png"])
    client = FakePortal()
    changed, _ = images.sync(client, "Bezierio", d, dry_run=True)
    assert changed and client.calls == []


def test_order_must_name_real_files(tmp_path):
    d = folder(tmp_path, {"a.png": b"A"}, ["a.png", "missing.png"])
    with pytest.raises(common.ReleaseError, match="missing.png"):
        images.sync(FakePortal(), "Bezierio", d)


class StoredButNotShown(FakePortal):
    """The portal keeps an image off the page: uploading it again is refused."""

    def __init__(self, stored):
        super().__init__()
        self.stored = stored

    def add_image(self, mod, path):
        image_id = hashlib.sha1(path.read_bytes()).hexdigest()
        if image_id in self.stored:
            import portal
            raise portal.PortalError("refused", "InvalidRequest", "Image already exists")
        return super().add_image(mod, path)

    def set_images(self, mod, ids):
        self.calls.append(("set", list(ids)))
        self.page = [{"id": i, "url": f"https://assets/{i}.png", "thumbnail": ""} for i in ids]
        return {"success": True, "images": self.page}


def test_an_image_stored_but_off_the_page_is_put_back(tmp_path):
    d = folder(tmp_path, {"a.png": b"A"}, ["a.png"])
    client = StoredButNotShown({sha(b"A")})
    changed, entries = images.sync(client, "Bezierio", d)
    assert changed and client.calls == [("set", [sha(b"A")])]
    assert entries[0]["id_on_mod_portal"] == sha(b"A") and entries[0]["url"] == f"https://assets/{sha(b'A')}.png"
