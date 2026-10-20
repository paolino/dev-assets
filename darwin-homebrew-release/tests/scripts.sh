#!/usr/bin/env bash
# The action's tarball smoke and published-asset check, on synthetic inputs:
# both tarball layouts pass, a missing command fails, and a published asset
# that is not the built tarball fails. Runs anywhere bash, tar and shasum do.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
scripts="$repo_root/darwin-homebrew-release/scripts"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

command_in() {
  mkdir -p "$1"
  printf '#!/bin/sh\necho "foo ran from $0"\n' >"$1/foo"
  chmod +x "$1/foo"
}
expect_fail() {
  local label="$1"
  shift
  if "$@" >"$tmp/$label.out" 2>&1; then
    echo "$label: expected a failure" >&2
    cat "$tmp/$label.out" >&2
    exit 1
  fi
}

# commands at the top of the tarball (the helper's own layout)
command_in "$tmp/flat/bin"
tar -czf "$tmp/flat.tar.gz" -C "$tmp/flat" .
INPUT_TARBALL="$tmp/flat.tar.gz" INPUT_INSTALLED_COMMANDS=foo \
  INPUT_TARBALL_SMOKE_SCRIPT='foo | grep -q "foo ran"' bash "$scripts/smoke-tarball.sh"

# commands in bin/ of one top directory (a caller-assembled bundle)
command_in "$tmp/nested/product-1.0/bin"
tar -czf "$tmp/nested.tar.gz" -C "$tmp/nested" product-1.0
INPUT_TARBALL="$tmp/nested.tar.gz" INPUT_INSTALLED_COMMANDS=foo \
  INPUT_TARBALL_SMOKE_SCRIPT='[ "$(basename "$DARWIN_BUNDLE_DIR")" = product-1.0 ] && foo | grep -q "foo ran"' \
  bash "$scripts/smoke-tarball.sh"

# a command the tarball does not carry
expect_fail missing-command env INPUT_TARBALL="$tmp/nested.tar.gz" INPUT_INSTALLED_COMMANDS="foo bar" \
  bash "$scripts/smoke-tarball.sh"

# the published asset: a gh that "downloads" a chosen file
mkdir -p "$tmp/shim"
cat >"$tmp/shim/gh" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
dir=""
pattern=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir) dir="$2"; shift 2 ;;
    --pattern) pattern="$2"; shift 2 ;;
    *) shift ;;
  esac
done
cp "$PUBLISHED" "$dir/$pattern"
SHIM
chmod +x "$tmp/shim/gh"
PATH="$tmp/shim:$PATH" PUBLISHED="$tmp/nested.tar.gz" INPUT_TAG=v1.0 \
  INPUT_TARBALL="$tmp/nested.tar.gz" INPUT_ASSET=product-1.0.tar.gz bash "$scripts/check-published-asset.sh"
expect_fail other-bytes env PATH="$tmp/shim:$PATH" PUBLISHED="$tmp/flat.tar.gz" INPUT_TAG=v1.0 \
  INPUT_TARBALL="$tmp/nested.tar.gz" INPUT_ASSET=product-1.0.tar.gz bash "$scripts/check-published-asset.sh"
expect_fail no-tag env PATH="$tmp/shim:$PATH" PUBLISHED="$tmp/nested.tar.gz" INPUT_TAG= \
  INPUT_TARBALL="$tmp/nested.tar.gz" INPUT_ASSET=product-1.0.tar.gz bash "$scripts/check-published-asset.sh"
echo "darwin-homebrew-release scripts: OK"
