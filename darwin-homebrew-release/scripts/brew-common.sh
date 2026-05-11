#!/usr/bin/env bash
brew_uninstall_if_installed() {
  local formula="$1"
  if brew list --formula "$formula" >/dev/null 2>&1; then
    brew uninstall --force "$formula"
  fi
}

brew_untap_if_tapped() {
  local tap="$1"
  if brew tap | grep -qx "$tap"; then
    brew untap "$tap"
  fi
}

cleanup_formulae() {
  for formula in ${INPUT_CLEANUP_FORMULAE:-}; do
    brew_uninstall_if_installed "$formula"
  done
}

tap_url() {
  printf 'https://github.com/%s.git\n' "$INPUT_TAP_REPOSITORY"
}

run_brew_smoke_script() {
  if [ -n "${INPUT_BREW_SMOKE_SCRIPT:-}" ]; then
    bash -euo pipefail -c "$INPUT_BREW_SMOKE_SCRIPT"
  fi
}
