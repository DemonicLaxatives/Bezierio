import io
import subprocess
import zipfile

import pytest

import common
import package
import validate


def test_debug_is_switched_off():
    assert "lib.debug = false" in package.release_debug_lua("local lib = {}\nlib.debug = true\nreturn lib\n")
    with pytest.raises(common.ReleaseError):
        package.release_debug_lua("local lib = {}\n")


def test_the_zip_has_one_folder_and_the_same_bytes_every_time():
    files = {"info.json": b'{"name": "Bezierio", "version": "0.2.0"}', common.DEBUG_LUA: b"lib.debug = true\n", "control.lua": b"--"}
    a = package.build_zip(files, "Bezierio", "0.2.0")
    assert a == package.build_zip(files, "Bezierio", "0.2.0")
    with zipfile.ZipFile(io.BytesIO(a)) as zf:
        assert sorted(zf.namelist()) == ["Bezierio_0.2.0/control.lua", "Bezierio_0.2.0/info.json", "Bezierio_0.2.0/scripts/debug.lua"]
        assert zf.read("Bezierio_0.2.0/scripts/debug.lua") == b"lib.debug = false\n"


def git(repo, *args):
    subprocess.run(["git", *args], cwd=repo, check=True, capture_output=True)


def test_package_leaves_out_what_gitattributes_marks(tmp_path):
    repo = tmp_path / "repo"
    (repo / "scripts").mkdir(parents=True)
    (repo / "tests").mkdir()
    (repo / "info.json").write_text('{"name": "Bezierio", "version": "0.2.0"}')
    (repo / "scripts" / "debug.lua").write_text("lib.debug = true\n")
    (repo / "tests" / "t.lua").write_text("--")
    (repo / ".gitattributes").write_text("tests/ export-ignore\n.gitattributes export-ignore\n")
    git(repo, "init", "-q")
    git(repo, "add", ".")
    git(repo, "-c", "user.name=t", "-c", "user.email=t@example.invalid", "commit", "-q", "-m", "x")
    path = package.package("HEAD", tmp_path / "dist", repo)
    assert path.name == "Bezierio_0.2.0.zip"
    with zipfile.ZipFile(path) as zf:
        names = zf.namelist()
    assert "Bezierio_0.2.0/tests/t.lua" not in names and "Bezierio_0.2.0/scripts/debug.lua" in names
    assert validate.zip_problems(path, {"name": "Bezierio", "version": "0.2.0"}) == []
