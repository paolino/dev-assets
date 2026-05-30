#!/usr/bin/env bash
# Local gate for paolino/dev-assets#26 — mirrors CI (shellcheck + tests +
# actionlint when available). Dropped in a `chore: drop gate.sh` commit before
# the PR is marked ready.
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
  echo "  - $t"
  bash "$t"
done

echo "==> actionlint"
if command -v actionlint >/dev/null 2>&1; then
  actionlint -color
else
  echo "actionlint not on PATH — skipping (CI enforces)" >&2
fi

echo "gate: OK"
