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
"${gh[@]}" release download "$dev_tag" \
  --dir "$download_dir" \
  --pattern "$exe-$artifact_version-x86_64-linux.*" \
  --clobber
ls -lh "$download_dir"
nix run --quiet ".#$smoke_app" -- \
  --artifacts-dir "$download_dir" \
  --artifact-version "$artifact_version" \
  --executable-name "$exe" \
  --usage-grep "$usage_grep"
