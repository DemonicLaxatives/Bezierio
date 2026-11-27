#!/usr/bin/env bash
# Push the current branch, then tag its HEAD and push the tag, which starts a
# workflow: portal-<name> syncs the mod portal page (portal.yml), vX.Y.Z makes a
# release (release.yml, after release/bump.py and a commit).
# Usage: release/push_tag.sh portal [name]      (default: today's date, then -1, -2, ...)
#        release/push_tag.sh release [X.Y.Z]   (default: the version in info.json)
set -euo pipefail
cd "$(dirname "$0")/.."
kind="${1:-}"
name="${2:-}"

taken() { git rev-parse -q --verify "refs/tags/$1" >/dev/null || git ls-remote --exit-code --tags origin "refs/tags/$1" >/dev/null; }

case "$kind" in
  portal)
    if [[ -n "$name" ]]; then
      tag="portal-${name#portal-}"
    else
      tag="portal-$(date +%F)"; n=0
      while taken "$tag"; do n=$((n + 1)); tag="portal-$(date +%F)-$n"; done
    fi
    # The workflow reads mod-portal/ at the tag.
    if ! git diff --quiet HEAD -- mod-portal; then
      echo "mod-portal/ has uncommitted changes: commit them first"; exit 1
    fi
    ;;
  release)
    version="${name#v}"
    [[ -n "$version" ]] || version="$(python3 -c 'import json; print(json.load(open("info.json"))["version"])')"
    tag="v$version"
    # What gets validated (the working tree) is what the tag holds.
    if ! git diff --quiet HEAD; then
      echo "uncommitted changes: commit them first (bump.py's info.json and changelog.txt too)"; exit 1
    fi
    python3 release/validate.py --tag "$tag"
    ;;
  *)
    echo "usage: $0 portal [name] | release [X.Y.Z]"; exit 2 ;;
esac

if taken "$tag"; then echo "tag $tag already exists"; exit 1; fi
branch="$(git symbolic-ref --short -q HEAD)" || { echo "not on a branch"; exit 1; }

echo "== push $branch"
git push origin "$branch"
echo "== tag $tag at $(git log -1 --format='%h %s')"
git tag "$tag"
git push origin "refs/tags/$tag"
