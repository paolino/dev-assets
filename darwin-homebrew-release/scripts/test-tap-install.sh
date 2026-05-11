#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
. "$ACTION_PATH/scripts/brew-common.sh"

formula_id="$(basename "$INPUT_FORMULA" .rb)"
formula_ref="${INPUT_TAP_NAME}/${formula_id}"

cleanup_formulae
brew_untap_if_tapped "$INPUT_TAP_NAME"
brew tap "$INPUT_TAP_NAME" "$(tap_url)"
brew install "$formula_ref"
brew test "$formula_ref"
run_brew_smoke_script
