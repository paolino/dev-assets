#!/usr/bin/env bash
set -euo pipefail

tag="${INPUT_TAG:-}"
if [ -z "$tag" ]; then
  echo "release publishing requires INPUT_TAG" >&2
  exit 1
fi

title="${INPUT_RELEASE_TITLE:-}"
if [ -z "$title" ]; then
  title="${GITHUB_REPOSITORY_NAME:-package} $tag"
fi

notes="$(mktemp)"
if [ -n "${INPUT_RELEASE_NOTES_COMMAND:-}" ]; then
  TAG="$tag" bash -euo pipefail -c "${INPUT_RELEASE_NOTES_COMMAND}" > "$notes"
else
  printf "Release %s\n" "$tag" > "$notes"
fi

gh release view "$tag" >/dev/null 2>&1 \
  || gh release create "$tag" \
    --title "$title" \
    --notes-file "$notes" \
  || gh release view "$tag" >/dev/null
gh release upload "$tag" "$INPUT_TARBALL" --clobber
