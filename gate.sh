#!/usr/bin/env bash
# Local gate for paolino/dev-assets#27. Dropped before mark-ready.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$root"

echo "==> shellcheck"
mapfile -t sh_files < <(find . -type f -name '*.sh' -not -path './.git/*')
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck --severity=error "${sh_files[@]}"
else
  echo "shellcheck not on PATH — skipping (CI enforces)" >&2
fi

echo "==> bash tests"
for t in setup-nix/tests/*.sh linux-release/tests/*.sh; do
  [ -e "$t" ] || continue
  echo "  - $t"; bash "$t"
done

echo "==> actionlint"
if command -v actionlint >/dev/null 2>&1; then
  actionlint -color
else
  echo "actionlint not on PATH — skipping (CI enforces)" >&2
fi

# Real nix self-test of the x86_64 artifact matrix, once the output exists.
if command -v nix >/dev/null 2>&1 && nix eval ".#packages.x86_64-linux.self-test.outPath" >/dev/null 2>&1; then
  echo "==> nix self-test matrix (.#self-test)"
  nix build --quiet ".#self-test" -o /tmp/dev-assets-selftest
  if nix eval ".#packages.x86_64-linux.self-test-smoke.outPath" >/dev/null 2>&1; then
    nix run --quiet ".#self-test-smoke"
  fi
else
  echo "==> self-test output not present yet — skipping nix matrix build"
fi

echo "gate: OK"
