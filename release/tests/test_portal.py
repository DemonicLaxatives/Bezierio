import pytest

import portal


class FakeResponse:
    def __init__(self, status, body):
        self.status_code, self.body = status, body

    def json(self):
        return self.body


class FakeSession:
    """Answers in order; records what was sent. Never touches the network."""

    def __init__(self, *answers):
        self.answers, self.sent = list(answers), []

    def get(self, url, timeout=None):
        self.sent.append({"url": url, "get": True})
        return FakeResponse(*self.answers.pop(0))

    def post(self, url, data=None, files=None, headers=None, timeout=None):
        self.sent.append({"url": url, "data": data, "files": files, "headers": headers})
        return FakeResponse(*self.answers.pop(0))


def test_upload_is_two_steps_with_the_key_only_on_the_first(tmp_path):
    zip_path = tmp_path / "Bezierio_0.2.0.zip"
    zip_path.write_bytes(b"zip")
    session = FakeSession((200, {"upload_url": "https://mods.factorio.com/upload/x"}), (200, {"success": True}))
    portal.Portal("key", session).upload_release("Bezierio", zip_path)
    first, second = session.sent
    assert first["url"].endswith("/releases/init_upload") and first["data"] == {"mod": "Bezierio"}
    assert first["headers"] == {"Authorization": "Bearer key"}
    assert second["url"] == "https://mods.factorio.com/upload/x" and "file" in second["files"]
    assert "Authorization" not in second["headers"]


def test_portal_errors_are_raised():
    session = FakeSession((403, {"error": "Forbidden", "message": "no permission"}))
    with pytest.raises(portal.PortalError, match="Forbidden"):
        portal.Portal("key", session).edit_details("Bezierio", {"summary": "x"})


def test_no_key_no_client(monkeypatch):
    monkeypatch.delenv("FACTORIO_API_KEY", raising=False)
    with pytest.raises(portal.PortalError):
        portal.Portal(session=FakeSession())


def test_images_are_set_in_order():
    session = FakeSession((200, {"success": True, "images": []}))
    portal.Portal("key", session).set_images("Bezierio", ["a", "b"])
    assert session.sent[0]["data"] == {"mod": "Bezierio", "images": "a,b"}


def test_the_page_is_read_without_the_key():
    session = FakeSession((200, {"images": [{"id": "a"}]}))
    assert portal.Portal("key", session).mod_info("Bezierio")["images"] == [{"id": "a"}]
    assert session.sent[0]["url"] == "https://mods.factorio.com/api/mods/Bezierio/full"
