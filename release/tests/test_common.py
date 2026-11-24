import pytest

import common

SEP = "-" * 99
GOOD = f"""{SEP}
Version: 0.2.0
Date: 25.11.2026
  Features:
    - A thing.
      Over two lines.
  Bugfixes:
    - Fixed a thing.
{SEP}
Version: 0.1.0
Date: 16.11.2023
  Info:
    - Initial release
"""


def test_a_good_changelog_has_no_problems():
    assert common.changelog_problems(GOOD) == []


@pytest.mark.parametrize("broken, expected", [
    (GOOD.replace(SEP, SEP[:-1], 1), "exactly 99 dashes"),
    (GOOD.replace("Version: 0.2.0", "Version 0.2.0"), "Version: X.Y.Z"),
    (GOOD.replace("Version: 0.2.0", "Version: 0.2"), "not a version"),
    (GOOD.replace("Version: 0.2.0", "Version: 0.1.0"), "appears twice"),
    (GOOD.replace("    - A thing.", "\t- A thing."), "tab"),
    (GOOD.replace("    - A thing.", "    - A thing. "), "trailing whitespace"),
    (GOOD.replace("  Features:\n", ""), "entry before any category"),
    (GOOD.replace("    - Fixed a thing.", "    - Fixed a thing.\n    - Fixed a thing."), "duplicate entry"),
    (GOOD.replace("  Features:", "  Features"), "not a category"),
    (GOOD.replace("Version: 0.2.0\nDate: 25.11.2026\n  Features:", "Version: 0.2.0\n  Features:\nDate: 25.11.2026"), "Date must come"),
])
def test_what_the_game_rejects_is_reported(broken, expected):
    assert any(expected in p for p in common.changelog_problems(broken))


def test_the_placeholder_is_a_problem_unless_allowed():
    text = GOOD.replace("Version: 0.2.0", "Version: 0.0.0")
    assert any("placeholder" in p for p in common.changelog_problems(text))
    assert common.changelog_problems(text, allow_unreleased=True) == []


def test_set_latest_turns_the_placeholder_into_the_version_with_a_date():
    text = GOOD.replace("Version: 0.2.0\nDate: 25.11.2026", "Version: 0.0.0")
    out = common.set_latest(text, "0.2.0", "01.12.2026")
    assert out.split("\n")[1:3] == ["Version: 0.2.0", "Date: 01.12.2026"]
    assert common.changelog_problems(out) == []


def test_set_latest_refuses_another_version():
    with pytest.raises(common.ReleaseError, match="add a section"):
        common.set_latest(GOOD, "0.3.0", "01.12.2026")


def test_section_text_is_the_entries():
    assert common.section_text(GOOD, "0.1.0") == "  Info:\n    - Initial release"
    with pytest.raises(common.ReleaseError):
        common.section_text(GOOD, "9.9.9")


def test_versions_are_checked():
    assert common.parse_version("1.2.3") == (1, 2, 3)
    for bad in ["1.2", "1.2.3.4", "a.b.c", "1.2.70000"]:
        with pytest.raises(common.ReleaseError):
            common.parse_version(bad)


def test_unreviewed_markers_outside_the_opening_comment():
    text = "; [unreviewed] explains the marker\n[titles]\n; ok\nx=1\n; check me [unreviewed]\ny=2\n"
    assert common.unreviewed_lines(text) == [5]
