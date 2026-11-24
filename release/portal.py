"""The Factorio mod portal API (https://wiki.factorio.com/Mod_upload_API and its
siblings): a thin client over requests. The API key comes from the
FACTORIO_API_KEY environment variable (a repository secret in CI); the session
can be replaced, so the tests never reach the real portal.
"""
import os

import requests

BASE = "https://mods.factorio.com/api/v2/mods"


class PortalError(Exception):
    """The portal refused (its `error` and `message`), or answered oddly."""


class Portal:
    def __init__(self, api_key=None, session=None, base=BASE):
        self.api_key = api_key if api_key is not None else os.environ.get("FACTORIO_API_KEY", "")
        if not self.api_key:
            raise PortalError("no API key: set FACTORIO_API_KEY")
        self.session = session or requests.Session()
        self.base = base

    def _post(self, url, data=None, files=None, auth=True):
        headers = {"Authorization": f"Bearer {self.api_key}"} if auth else {}
        response = self.session.post(url, data=data, files=files, headers=headers, timeout=120)
        try:
            body = response.json()
        except ValueError:
            raise PortalError(f"{url}: HTTP {response.status_code}, not JSON")
        if response.status_code >= 400 or "error" in body:
            raise PortalError(f"{url}: {body.get('error', response.status_code)}: {body.get('message', '')}")
        return body

    def upload_release(self, mod, zip_path):
        """Upload a release zip (key permission: ModPortal: Upload Mods)."""
        start = self._post(f"{self.base}/releases/init_upload", data={"mod": mod})
        url = start.get("upload_url")
        if not url:
            raise PortalError("init_upload: no upload_url")
        with open(zip_path, "rb") as f:
            done = self._post(url, files={"file": (os.path.basename(zip_path), f, "application/zip")}, auth=False)
        if not done.get("success"):
            raise PortalError("upload: no success")
        return done

    def edit_details(self, mod, fields):
        """Set mod page fields: summary, description, faq, ... (ModPortal: Edit Mods)."""
        data = {"mod": mod}
        data.update(fields)
        return self._post(f"{self.base}/edit_details", data=data)

    def add_image(self, mod, image_path):
        """Upload an image; its {id, url, thumbnail} (ModPortal: Edit Mods)."""
        start = self._post(f"{self.base}/images/add", data={"mod": mod})
        url = start.get("upload_url")
        if not url:
            raise PortalError("images/add: no upload_url")
        with open(image_path, "rb") as f:
            return self._post(url, files={"image": (os.path.basename(image_path), f)}, auth=False)

    def set_images(self, mod, ids):
        """The page's images, in this order (ids left out are removed)."""
        return self._post(f"{self.base}/images/edit", data={"mod": mod, "images": ",".join(ids)})
