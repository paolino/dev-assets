#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
. "$ACTION_PATH/scripts/brew-common.sh"

formula_id="$(basename "$INPUT_FORMULA" .rb)"
formula_ref="${INPUT_TAP_NAME}/${formula_id}"

cleanup_formulae
brew_untap_if_tapped "$INPUT_TAP_NAME"
brew tap "$INPUT_TAP_NAME" "$(tap_url)"
# Homebrew now refuses to load a formula from a third-party tap unless it is
# explicitly trusted. This is our own tap, so trust it before installing.
# HOMEBREW_NO_REQUIRE_TAP_TRUST is the documented guaranteed fallback on the
# enforcing brew version; `brew trust` is the forward-looking path (guarded so
# it no-ops on brew versions that predate the command / the policy).
export HOMEBREW_NO_REQUIRE_TAP_TRUST=1
brew trust "$INPUT_TAP_NAME" 2>/dev/null || true
brew install "$formula_ref"
brew test "$formula_ref"
run_brew_smoke_script
