#!/usr/bin/env bash
set -euo pipefail

tmpdir="$(mktemp -d)"
tar xzf "$INPUT_TARBALL" -C "$tmpdir"

# The commands sit in bin/ at the top of the tarball, or in bin/ of its one
# top directory (a bundle the caller assembled; see bundleTarball).
root="$tmpdir"
if [ ! -d "$root/bin" ]; then
  entries=("$tmpdir"/*)
  if [ "${#entries[@]}" -eq 1 ] && [ -d "${entries[0]}/bin" ]; then
    root="${entries[0]}"
  fi
fi

for command in ${INPUT_INSTALLED_COMMANDS}; do
  test -x "$root/bin/$command"
done

if [ -n "${INPUT_TARBALL_SMOKE_SCRIPT:-}" ]; then
  export DARWIN_BUNDLE_DIR="$root"
  export PATH="$root/bin:$PATH"
  bash -euo pipefail -c "$INPUT_TARBALL_SMOKE_SCRIPT"
fi
