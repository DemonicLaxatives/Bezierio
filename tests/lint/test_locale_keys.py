import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import locale_keys  # noqa: E402

LOCALE = "; comment\n[tooltip]\n; about x\nx=X\n[label]\ny=Y\n"


def test_written_keys_must_exist():
    sources = [("a.lua", 'local a = { "tooltip.x" }\nlocal b = { "label.z" }\n')]
    assert locale_keys.missing_keys(LOCALE, sources) == [("a.lua", 2, "label.z")]


def test_prefixes_and_other_strings_are_skipped():
    sources = [("a.lua", 'local a = { "tooltip." .. name }\nlocal b = { "label.pre-" .. mode }\nlocal c = "scripts.gui.window"\n')]
    assert locale_keys.missing_keys(LOCALE, sources) == []
