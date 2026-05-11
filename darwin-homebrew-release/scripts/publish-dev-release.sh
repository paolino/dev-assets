#!/usr/bin/env bash
set -euo pipefail

dev_tag="${INPUT_DEV_TAG:-dev-homebrew}"
formula_id="$(basename "${INPUT_FORMULA}" .rb)"
title="${INPUT_DEV_RELEASE_TITLE:-}"
if [ -z "$title" ]; then
  title="${GITHUB_REPOSITORY_NAME:-package} dev Homebrew"
fi

notes="$(mktemp)"
{
  printf "Development Homebrew build for \`%s\`.\n\n" "$GITHUB_SHA"
  printf "Formula: \`%s\`\n" "$formula_id"
  printf "Asset: \`%s\`\n" "$INPUT_ASSET"
} > "$notes"

git tag -f "$dev_tag" "$GITHUB_SHA"
git push --force origin "refs/tags/$dev_tag"

gh release view "$dev_tag" >/dev/null 2>&1 \
  || gh release create "$dev_tag" \
    --title "$title" \
    --notes-file "$notes" \
    --prerelease
gh release edit "$dev_tag" \
  --title "$title" \
  --notes-file "$notes" \
  --prerelease
gh release upload "$dev_tag" "$INPUT_TARBALL" --clobber
