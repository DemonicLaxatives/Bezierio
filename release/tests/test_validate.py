import io
import zipfile

import validate
from test_common import GOOD

INFO = {"name": "Bezierio", "version": "0.2.0"}
LOCALE = "; explains [unreviewed]\n[titles]\n; checked\nx=1\n"


def test_a_ready_release_passes():
    assert validate.repo_problems("v0.2.0", INFO, GOOD, LOCALE) == []


def test_mismatches_are_reported():
    problems = validate.repo_problems("v0.3.0", INFO, GOOD, LOCALE + "; still [unreviewed]\ny=2\n")
    assert any("info.json" in p for p in problems)
    assert any("changelog.txt starts with" in p for p in problems)
    assert any("unreviewed" in p for p in problems)
    assert validate.repo_problems("0.2.0", INFO, GOOD, LOCALE) == ["tag '0.2.0' isn't vX.Y.Z"]


def make_zip(tmp_path, entries):
    path = tmp_path / "z.zip"
    with zipfile.ZipFile(path, "w") as zf:
        for name, data in entries.items():
            zf.writestr(name, data)
    return path


def test_zip_checks(tmp_path):
    good = {"Bezierio_0.2.0/info.json": '{"version": "0.2.0"}', "Bezierio_0.2.0/scripts/debug.lua": "lib.debug = false\n"}
    assert validate.zip_problems(make_zip(tmp_path, good), INFO) == []
    bad = dict(good)
    bad["Bezierio_0.2.0/scripts/debug.lua"] = "lib.debug = true\n"
    bad["Bezierio_0.2.0/tests/x.lua"] = "--"
    bad["stray.txt"] = "x"
    problems = validate.zip_problems(make_zip(tmp_path, bad), INFO)
    assert any("debug" in p for p in problems)
    assert any("don't ship" in p for p in problems)
    assert any("outside" in p for p in problems)
