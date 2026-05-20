#!/usr/bin/env bash
set -euo pipefail

mode="${INPUT_MODE:-}"
tag="${INPUT_TAG:-}"
exe="${INPUT_EXECUTABLE_NAME:-}"
usage_grep="${INPUT_USAGE_GREP:-}"
version_command="${INPUT_RELEASE_VERSION_COMMAND:-}"
smoke_app="${INPUT_SMOKE_APP:-linux-artifact-smoke}"

if [ -z "$exe" ]; then
  echo "executable-name is required" >&2
  exit 1
fi
if [ -z "$usage_grep" ]; then
  echo "usage-grep is required" >&2
  exit 1
fi
if [ -z "$version_command" ]; then
  echo "release-version-command is required" >&2
  exit 1
fi

case "$mode" in
  release)
    if [ -z "$tag" ]; then
      echo "release mode requires a tag input or a tag push" >&2
      exit 1
    fi
    if [ -n "${INPUT_RELEASE_CHECK_COMMAND:-}" ]; then
      TAG="$tag" bash -euo pipefail -c "${INPUT_RELEASE_CHECK_COMMAND}"
    fi
    base_version="$(TAG="$tag" bash -euo pipefail -c "$version_command")"
    artifact_version="$base_version"
    package="${INPUT_RELEASE_OUTPUT}"
    artifact_name="${INPUT_ARTIFACT_NAME_PREFIX}-$exe"
    ;;
  dev-linux)
    base_version="$(TAG="$tag" bash -euo pipefail -c "$version_command")"
    short_sha="$(git rev-parse --short=7 HEAD)"
    artifact_version="${base_version}-${short_sha}"
    package="${INPUT_DEV_OUTPUT}"
    artifact_name="${INPUT_DEV_ARTIFACT_NAME_PREFIX}-$exe"
    ;;
  *)
    echo "unsupported Linux release mode: $mode" >&2
    exit 1
    ;;
esac

out_link="${RUNNER_TEMP:-/tmp}/${package}"
nix build --quiet --print-out-paths \
  --out-link "$out_link" \
  ".#$package" >/dev/null

artifact_dir="$(readlink -f "$out_link")"

nix run --quiet ".#${smoke_app}" -- \
  --artifacts-dir "$artifact_dir" \
  --artifact-version "$artifact_version" \
  --executable-name "$exe" \
  --usage-grep "$usage_grep"

rm -rf artifacts
mkdir -p artifacts
cp -L "$artifact_dir"/* artifacts/
ls -lh artifacts/

artifacts_dir_abs="$(readlink -f artifacts)"

{
  printf 'artifact_version=%s\n' "$artifact_version"
  printf 'artifact_name=%s\n' "$artifact_name"
  printf 'artifacts_dir=%s\n' "$artifacts_dir_abs"
} >> "$GITHUB_OUTPUT"
