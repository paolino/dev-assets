#!/usr/bin/env bash
set -euo pipefail

mode="${INPUT_MODE:-}"
tag="${INPUT_TAG:-}"

case "$mode" in
  release)
    if [ -z "$tag" ]; then
      echo "release mode requires a tag input or a tag push" >&2
      exit 1
    fi
    if [ -n "${INPUT_RELEASE_CHECK_COMMAND:-}" ]; then
      TAG="$tag" bash -euo pipefail -c "${INPUT_RELEASE_CHECK_COMMAND}"
    fi
    package="${INPUT_RELEASE_PACKAGE}"
    formula_name="${INPUT_RELEASE_FORMULA}"
    artifact_name="${INPUT_RELEASE_ARTIFACT_NAME}"
    ;;
  dev-homebrew)
    package="${INPUT_DEV_PACKAGE}"
    formula_name="${INPUT_DEV_FORMULA}"
    artifact_name="${INPUT_DEV_ARTIFACT_NAME}"
    ;;
  *)
    echo "unsupported Darwin release mode: $mode" >&2
    exit 1
    ;;
esac

out_link="${RUNNER_TEMP:-/tmp}/${package}"
artifacts="$(
  nix build -L --print-out-paths \
    --out-link "$out_link" \
    ".#$package"
)"
tarball="$(
  find "$artifacts" -maxdepth 1 -type f \
    -name "${INPUT_TARBALL_PATTERN}" \
    -print -quit
)"
formula="$artifacts/$formula_name"

if [ -z "$tarball" ]; then
  echo "missing Darwin tarball in $artifacts" >&2
  exit 1
fi
if [ ! -f "$formula" ]; then
  echo "missing Homebrew formula: $formula" >&2
  exit 1
fi

cat "$artifacts/SHA256SUMS"
{
  printf 'path=%s\n' "$artifacts"
  printf 'tarball=%s\n' "$tarball"
  printf 'formula=%s\n' "$formula"
  printf 'asset=%s\n' "$(basename "$tarball")"
  printf 'artifact_name=%s\n' "$artifact_name"
} >> "$GITHUB_OUTPUT"
