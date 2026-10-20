#!/usr/bin/env bash
# The caller's release job published the tarball (upload-assets: no): the
# formula is pushed only when the release's asset of that name is byte for
# byte the tarball the formula's checksum was computed from.
set -euo pipefail

for name in INPUT_TAG INPUT_TARBALL INPUT_ASSET; do
  if [ -z "${!name:-}" ]; then
    echo "check-published-asset requires $name" >&2
    exit 1
  fi
done

download="$(mktemp -d)"
trap 'rm -rf "$download"' EXIT
gh release download "$INPUT_TAG" --dir "$download" --pattern "$INPUT_ASSET"
published="$(shasum -a 256 "$download/$INPUT_ASSET" | cut -d' ' -f1)"
built="$(shasum -a 256 "$INPUT_TARBALL" | cut -d' ' -f1)"
if [ "$published" != "$built" ]; then
  echo "the release's $INPUT_ASSET has checksum $published; the formula names $built" >&2
  exit 1
fi
echo "the release's $INPUT_ASSET is the tarball the formula names ($built)"
