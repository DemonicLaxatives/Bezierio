"""What the release scripts share: the repository's paths, info.json, the
changelog (Factorio's strict format), and the locale review markers.

Pure functions on text where possible, so the tests don't need a repository.
"""
import json
import pathlib
import re

REPO = pathlib.Path(__file__).resolve().parents[1]
INFO = REPO / "info.json"
CHANGELOG = REPO / "changelog.txt"
LOCALE = REPO / "locale" / "en" / "Bezierio.cfg"
DEBUG_LUA = "scripts/debug.lua"

#: The changelog's placeholder for the version being worked on (invalid to the
#: game, so it can't slip into a release): bump.py turns it into the real one.
UNRELEASED = "0.0.0"

SEPARATOR = "-" * 99
VERSION_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")


class ReleaseError(Exception):
    """Something that must stop a release, with what to do about it."""


def parse_version(text):
    """(major, minor, patch) for "X.Y.Z" (each 0..65535), or ReleaseError."""
    m = VERSION_RE.match(text or "")
    if not m or any(int(n) > 65535 for n in m.groups()):
        raise ReleaseError(f"not a version (X.Y.Z, numbers up to 65535): {text!r}")
    return tuple(int(n) for n in m.groups())


def read_info(path=INFO):
    return json.loads(pathlib.Path(path).read_text(encoding="utf-8"))


def write_info(info, path=INFO):
    pathlib.Path(path).write_text(json.dumps(info, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


# Changelog -----------------------------------------------------------------------

def changelog_sections(text):
    """The sections as [{"version", "date", "start" (line index), "lines"}], in
    file order (no checks: see changelog_problems)."""
    lines = text.split("\n")
    sections = []
    for i, line in enumerate(lines):
        if line == SEPARATOR:
            sections.append({"start": i, "lines": [], "version": None, "date": None})
        elif sections:
            sections[-1]["lines"].append(line)
    for s in sections:
        body = s["lines"]
        if body and body[0].startswith("Version: "):
            s["version"] = body[0][len("Version: "):]
        for line in body[1:]:
            if line.startswith("Date: "):
                s["date"] = line[len("Date: "):]
    return sections


def changelog_problems(text, allow_unreleased=False):
    """What the game would reject (lua-api.factorio.com, changelog format), as
    messages with line numbers; [] when the file is fine."""
    problems = []
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines = lines[:-1]  # (the final newline)
    if not lines or lines[0] != SEPARATOR:
        problems.append("line 1: must be the separator (99 dashes)")
    seen_versions, section_lines = set(), None
    state = "start"  # start, version, body
    category, entries = None, set()
    for n, line in enumerate(lines, 1):
        if "\t" in line:
            problems.append(f"line {n}: tab")
        if line != line.rstrip():
            problems.append(f"line {n}: trailing whitespace")
        if line.startswith("-") and set(line) == {"-"}:
            if line != SEPARATOR:
                problems.append(f"line {n}: separator must be exactly 99 dashes, not {len(line)}")
            state, category, entries, section_lines = "version", None, set(), 0
            continue
        if state == "start":
            continue  # (reported above)
        if state == "version":
            if not line.startswith("Version: "):
                problems.append(f"line {n}: the line after a separator must be 'Version: X.Y.Z'")
            else:
                v = line[len("Version: "):]
                try:
                    parse_version(v)
                    if v == UNRELEASED and not allow_unreleased:
                        problems.append(f"line {n}: version {UNRELEASED} is the unreleased placeholder (run bump.py)")
                except ReleaseError as e:
                    problems.append(f"line {n}: {e}")
                if v in seen_versions:
                    problems.append(f"line {n}: version {v} appears twice")
                seen_versions.add(v)
            state = "body"
            continue
        if not line.strip():
            continue
        if line.startswith("Date: "):
            section_lines += 1
            if category is not None or section_lines > 1:
                problems.append(f"line {n}: Date must come right after Version, once")
            continue
        section_lines += 1
        if re.match(r"^  [^ ].*:$", line):
            category, entries = line[2:-1], set()
        elif line.startswith("    - "):
            if category is None:
                problems.append(f"line {n}: entry before any category")
            elif line in entries:
                problems.append(f"line {n}: duplicate entry in {category}")
            entries.add(line)
        elif line.startswith("      ") and not line.startswith("       "):
            if category is None:
                problems.append(f"line {n}: continuation before any entry")
        else:
            problems.append(f"line {n}: not a category (2 spaces, ends with ':'), entry (4 spaces, '- ') or continuation (6 spaces)")
    return problems


def latest_version(text):
    """The version of the changelog's first section, or None."""
    sections = changelog_sections(text)
    return sections[0]["version"] if sections else None


def set_latest(text, version, date):
    """The changelog with its first section's version set to `version` (it must
    be the placeholder or that version already) and its date to `date`."""
    sections = changelog_sections(text)
    if not sections:
        raise ReleaseError("changelog.txt has no sections")
    current = sections[0]["version"]
    if current not in (UNRELEASED, version):
        raise ReleaseError(
            f"changelog.txt starts with version {current}: add a section for {version} "
            f"(or {UNRELEASED} while it's unreleased) at the top first")
    lines = text.split("\n")
    start = sections[0]["start"]
    lines[start + 1] = f"Version: {version}"
    if lines[start + 2].startswith("Date: "):
        lines[start + 2] = f"Date: {date}"
    else:
        lines.insert(start + 2, f"Date: {date}")
    return "\n".join(lines)


def section_text(text, version):
    """A version's entries (without the separator and Version / Date lines), for
    release notes."""
    for s in changelog_sections(text):
        if s["version"] == version:
            body = [l for l in s["lines"][1:] if not l.startswith("Date: ")]
            return "\n".join(body).strip("\n")
    raise ReleaseError(f"changelog.txt has no section for {version}")


# Locale ---------------------------------------------------------------------------

REVIEW_MARK = "[unreviewed]"


def unreviewed_lines(text):
    """Line numbers of comments still marked unreviewed, except in the file's
    opening comment (which explains the marker)."""
    out, header = [], True
    for n, line in enumerate(text.split("\n"), 1):
        if header and line.startswith(";"):
            continue
        header = False
        if REVIEW_MARK in line:
            out.append(n)
    return out
