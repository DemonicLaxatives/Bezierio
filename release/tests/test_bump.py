import json

import pytest

import bump
import common
from test_common import GOOD


def files(tmp_path, changelog):
    info, log = tmp_path / "info.json", tmp_path / "changelog.txt"
    info.write_text(json.dumps({"name": "Bezierio", "version": "0.1.0"}))
    log.write_text(changelog)
    return info, log


def test_bump_sets_both(tmp_path):
    info, log = files(tmp_path, GOOD.replace("Version: 0.2.0\nDate: 25.11.2026", "Version: 0.0.0"))
    bump.bump("0.2.0", "01.12.2026", info, log)
    assert json.loads(info.read_text())["version"] == "0.2.0"
    assert common.latest_version(log.read_text()) == "0.2.0"
    assert "Date: 01.12.2026" in log.read_text()


def test_bump_writes_nothing_when_the_changelog_isnt_ready(tmp_path):
    info, log = files(tmp_path, GOOD)
    with pytest.raises(common.ReleaseError):
        bump.bump("0.3.0", "01.12.2026", info, log)
    assert json.loads(info.read_text())["version"] == "0.1.0"
    assert log.read_text() == GOOD
