#!/usr/bin/env bash
set -euo pipefail

# assert-no-source-ghc.sh <flake-attr> [<flake-attr>...]
#
# Cachix gate: fail fast when `nix build --dry-run` would BUILD a GHC
# derivation from source (a cache miss) rather than FETCH it from a
# substituter. A silent GHC cache miss burns 30-40 min of runner time; this
# turns it into an immediate, explanatory failure. See paolino/dev-assets#26.

if [ "$#" -eq 0 ]; then
  echo "usage: assert-no-source-ghc.sh <flake-attr> [<flake-attr>...]" >&2
  exit 2
fi

# nix writes the build/fetch plan to stderr.
plan="$(nix build --dry-run "$@" 2>&1 || true)"

# Keep only the indented store paths inside the "will be built" section;
# the "will be fetched" section (substituted from cache) is fine.
built="$(printf '%s\n' "$plan" | awk '
  /will be fetched/ { inblock = 0 }
  /will be built:/  { inblock = 1; next }
  inblock && /^[[:space:]]+\/nix\/store\// { print }
')"

ghc="$(printf '%s\n' "$built" | grep -E '/nix/store/.*-ghc-[0-9][^[:space:]]*' || true)"

if [ -n "$ghc" ]; then
  echo "cachix gate FAILED: GHC would be built from source (cache miss):" >&2
  printf '  %s\n' "$ghc" >&2
  echo "Warm it via lambdasistemi/cachix-warmup before releasing." >&2
  exit 1
fi

echo "cachix gate OK: GHC is cached (no source build planned)"
