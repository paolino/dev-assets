#!/usr/bin/env bash
set -euo pipefail

dev_tag="${INPUT_DEV_TAG:-}"
exe="${INPUT_EXECUTABLE_NAME:-}"
artifact_version="${INPUT_ARTIFACT_VERSION:-}"
usage_grep="${INPUT_USAGE_GREP:-}"
smoke_app="${INPUT_SMOKE_APP:-linux-artifact-smoke}"

if [ -z "$dev_tag" ] || [ -z "$exe" ] || [ -z "$artifact_version" ] || [ -z "$usage_grep" ]; then
  echo "smoke-dev-release requires DEV_TAG, EXECUTABLE_NAME, ARTIFACT_VERSION, USAGE_GREP" >&2
  exit 1
fi

download_dir="$(mktemp -d)"
gh=(nix --quiet shell nixpkgs#gh -c gh)
# every command of the product has its own AppImage; the packages carry the
# product name
patterns=(--pattern "$exe-$artifact_version-x86_64-linux.*")
IFS=, read -ra commands <<< "${INPUT_COMMANDS:-}"
for command in "${commands[@]}"; do
  [ "$command" = "$exe" ] || patterns+=(--pattern "$command-$artifact_version-x86_64-linux.*")
done
"${gh[@]}" release download "$dev_tag" \
  --dir "$download_dir" \
  "${patterns[@]}" \
  --clobber
ls -lh "$download_dir"
smoke=(
  --artifacts-dir "$download_dir"
  --artifact-version "$artifact_version"
  --executable-name "$exe"
  --usage-grep "$usage_grep"
)
if [ -n "${INPUT_COMMANDS:-}" ]; then smoke+=(--commands "$INPUT_COMMANDS"); fi
if [ -n "${INPUT_SMOKE_ARGS:-}" ]; then smoke+=(--smoke-args "$INPUT_SMOKE_ARGS"); fi
nix run --quiet ".#$smoke_app" -- "${smoke[@]}"
