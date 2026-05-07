#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
preview_script="$repo_root/static-preview/scripts/preview.sh"
tmp="$(mktemp -d)"

cleanup() {
  chmod -R u+w "$tmp" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

source_path="$tmp/source"
preview_root="$tmp/previews"
preview_parent="$preview_root/example/repo"
preview_dir="$preview_parent/pr-42"
stale_nested="$preview_dir/freeze-workflow"

mkdir -p "$source_path/assets" "$stale_nested"
printf 'fresh preview\n' >"$source_path/index.html"
printf 'fresh asset\n' >"$source_path/assets/app.txt"
printf 'stale preview\n' >"$stale_nested/index.html"
chmod 555 "$stale_nested"
chmod 777 "$preview_parent"

INPUT_MODE=publish \
INPUT_PATH="$source_path" \
INPUT_PREVIEW_ROOT="$preview_root" \
INPUT_PREVIEW_HOST="https://preview.example.invalid" \
INPUT_OWNER=example \
INPUT_REPOSITORY=repo \
INPUT_PR_NUMBER=42 \
GITHUB_RUN_ID=12345 \
GITHUB_RUN_ATTEMPT=1 \
bash "$preview_script" >"$tmp/output.log"

test -f "$preview_dir/index.html"
test -f "$preview_dir/assets/app.txt"
if [[ -e "$preview_dir/freeze-workflow/index.html" ]]; then
  echo "stale preview file remained in published preview" >&2
  exit 1
fi
grep -q 'fresh preview' "$preview_dir/index.html"

old_preview="$(find "$preview_parent" -maxdepth 1 -name 'pr-42.old-*' -print -quit)"
test -n "$old_preview"
chmod -R u+w "$old_preview"

printf 'newer preview\n' >"$source_path/index.html"

INPUT_MODE=publish \
INPUT_PATH="$source_path" \
INPUT_PREVIEW_ROOT="$preview_root" \
INPUT_PREVIEW_HOST="https://preview.example.invalid" \
INPUT_OWNER=example \
INPUT_REPOSITORY=repo \
INPUT_PR_NUMBER=42 \
GITHUB_RUN_ID=12346 \
GITHUB_RUN_ATTEMPT=1 \
bash "$preview_script" >"$tmp/output-2.log"

test -f "$preview_dir/index.html"
grep -q 'newer preview' "$preview_dir/index.html"
if find "$preview_parent" -maxdepth 1 -name 'pr-42.old-*' -print -quit | grep -q .; then
  echo "old preview backups were not cleaned up" >&2
  exit 1
fi
