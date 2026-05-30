#!/usr/bin/env bash
set -euo pipefail

# Tests setup-nix/scripts/assert-no-source-ghc.sh. PATH-shims `nix` so a
# `nix build --dry-run` emits a fixed plan; no real store needed.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
script="$repo_root/setup-nix/scripts/assert-no-source-ghc.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
shim="$tmp/bin"
mkdir -p "$shim"

write_nix_shim() {
  cat >"$shim/nix"
  chmod +x "$shim/nix"
}

# Case 1: GHC in the "will be built" section -> must FAIL (exit non-zero).
write_nix_shim <<'NIX'
#!/usr/bin/env bash
cat >&2 <<'OUT'
these 2 derivations will be built:
  /nix/store/aaa-ghc-9.12.3.drv
  /nix/store/bbb-foo-0.1.drv
these 3 paths will be fetched (10.00 MiB download):
  /nix/store/ccc-zlib-1.3
OUT
exit 0
NIX
if PATH="$shim:$PATH" bash "$script" '.#foo' >/dev/null 2>&1; then
  echo "FAIL: expected non-zero exit when GHC is built from source" >&2
  exit 1
fi

# Case 2: GHC only in the "will be fetched" section -> must PASS (exit 0).
write_nix_shim <<'NIX'
#!/usr/bin/env bash
cat >&2 <<'OUT'
these 1 derivations will be built:
  /nix/store/bbb-foo-0.1.drv
these 2 paths will be fetched (200.00 MiB download):
  /nix/store/aaa-ghc-9.12.3
  /nix/store/ccc-zlib-1.3
OUT
exit 0
NIX
if ! PATH="$shim:$PATH" bash "$script" '.#foo' >/dev/null 2>&1; then
  echo "FAIL: expected zero exit when GHC is only fetched from cache" >&2
  exit 1
fi

# Case 3: only the cheap GHC *env wrapper* is built (the real ghc-<ver>
# compiler is fetched). The wrapper name embeds "-ghc-9.12.3" but is not the
# compiler -> must PASS (exit 0). Guards against flagging every haskell.nix
# build, whose ghc-shell-for-packages env is always rebuilt locally.
write_nix_shim <<'NIX'
#!/usr/bin/env bash
cat >&2 <<'OUT'
these 1 derivations will be built:
  /nix/store/ydvniszx36gp9zcfn3crlw9z85qk06v0-ghc-shell-for-packages-ghc-9.12.3-env.drv
these 2 paths will be fetched (200.00 MiB download):
  /nix/store/qq98gxr9ydjvfdw6bs4hyz4jfi5pa73f-ghc-9.12.3
  /nix/store/ccc-zlib-1.3
OUT
exit 0
NIX
if ! PATH="$shim:$PATH" bash "$script" '.#foo' >/dev/null 2>&1; then
  echo "FAIL: expected zero exit when only the ghc env wrapper is built" >&2
  exit 1
fi

echo "assert-no-source-ghc test: OK"
