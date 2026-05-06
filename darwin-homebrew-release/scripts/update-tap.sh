#!/usr/bin/env bash
set -euo pipefail

if [ -z "${INPUT_TAP_TOKEN:-}" ]; then
  echo "tap update requires tap-token" >&2
  exit 1
fi

formula_name="$(basename "$INPUT_FORMULA")"
tap_dir="$(mktemp -d)"

git clone "https://x-access-token:${INPUT_TAP_TOKEN}@github.com/${INPUT_TAP_REPOSITORY}.git" "$tap_dir"
mkdir -p "$tap_dir/Formula"
cp "$INPUT_FORMULA" "$tap_dir/Formula/$formula_name"

cd "$tap_dir"
git config user.name "github-actions"
git config user.email "actions@github.com"
git add "Formula/$formula_name"

if [ -n "${INPUT_TAG:-}" ]; then
  commit_message="update ${formula_name%.rb} to ${INPUT_TAG}"
else
  commit_message="update ${formula_name%.rb} dev to ${GITHUB_SHA::12}"
fi

git diff --cached --quiet || git commit -m "$commit_message"
git push
