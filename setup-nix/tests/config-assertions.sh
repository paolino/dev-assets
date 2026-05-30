#!/usr/bin/env bash
set -euo pipefail

# Asserts setup-nix/action.yaml hardens cachix per paolino/dev-assets#26:
#   - paolino.cachix.org is declared as a read substituter directly
#     (not only as a side effect of the cachix-action push step), and
#   - its public key is a trusted key, and
#   - push degrades to read-only when no token is present (skipPush wired).
# No nix needed: this is a static assertion over the action YAML.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
action="$repo_root/setup-nix/action.yaml"

fail() { echo "ASSERTION FAILED: $1" >&2; exit 1; }

[ -f "$action" ] || fail "missing $action"

grep -Eq 'substituters[^#]*https://paolino\.cachix\.org' "$action" \
  || fail "paolino.cachix.org not declared as a read substituter"

grep -Eq 'trusted-public-keys[^#]*paolino\.cachix\.org-1:ecmgO3CXdgSWA2cHlm4srknd/cLFMLmK3i3NrzeDFaE=' "$action" \
  || fail "paolino public key not declared as a trusted key"

grep -Eq 'skipPush:' "$action" \
  || fail "cachix-action skipPush toggle not wired (push must degrade to read-only without a token)"

echo "config-assertions: OK"
