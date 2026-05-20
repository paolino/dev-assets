#!/usr/bin/env bash
set -euo pipefail

dev_tag="${INPUT_DEV_TAG:-}"
exe="${INPUT_EXECUTABLE_NAME:-}"
artifacts_dir="${INPUT_ARTIFACTS_DIR:-}"

if [ -z "$dev_tag" ]; then
  echo "dev-linux publishing requires INPUT_DEV_TAG" >&2
  exit 1
fi
if [ -z "$exe" ]; then
  echo "dev-linux publishing requires INPUT_EXECUTABLE_NAME" >&2
  exit 1
fi
if [ -z "$artifacts_dir" ]; then
  echo "dev-linux publishing requires INPUT_ARTIFACTS_DIR" >&2
  exit 1
fi

title="${INPUT_DEV_RELEASE_TITLE:-}"
if [ -z "$title" ]; then
  title="$exe dev Linux bundles"
fi

notes="$(mktemp)"
{
  echo "Development Linux $exe bundles for $GITHUB_SHA"
  echo
  echo "Built from $GITHUB_REF."
} > "$notes"

git tag -f "$dev_tag" HEAD
git push --force origin "refs/tags/$dev_tag"

gh=(nix --quiet shell nixpkgs#gh -c gh)
"${gh[@]}" release view "$dev_tag" >/dev/null 2>&1 \
  || "${gh[@]}" release create "$dev_tag" \
    --title "$title" \
    --notes-file "$notes" \
    --prerelease
"${gh[@]}" release edit "$dev_tag" \
  --title "$title" \
  --notes-file "$notes" \
  --prerelease
"${gh[@]}" release upload "$dev_tag" "$artifacts_dir"/* --clobber
