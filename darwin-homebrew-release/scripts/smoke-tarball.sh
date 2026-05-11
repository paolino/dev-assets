#!/usr/bin/env bash
set -euo pipefail

tmpdir="$(mktemp -d)"
tar xzf "$INPUT_TARBALL" -C "$tmpdir"

for command in ${INPUT_INSTALLED_COMMANDS}; do
  test -x "$tmpdir/bin/$command"
done

if [ -n "${INPUT_TARBALL_SMOKE_SCRIPT:-}" ]; then
  export DARWIN_BUNDLE_DIR="$tmpdir"
  export PATH="$tmpdir/bin:$PATH"
  bash -euo pipefail -c "$INPUT_TARBALL_SMOKE_SCRIPT"
fi
