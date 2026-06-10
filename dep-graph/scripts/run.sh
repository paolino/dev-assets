#!/usr/bin/env bash
# Dispatch the language-specific dependency-graph extractor and write Markdown.
#
# Tools (babashka, gh, jq, git) are taken from PATH when all present, otherwise
# provided on the fly via `nix shell`. Nix itself must be available (use the
# paolino/dev-assets/setup-nix action, or a nixos runner). `gh` authenticates
# with GH_TOKEN; public dependency repos need only the default GITHUB_TOKEN.
set -euo pipefail

LANGUAGE="${INPUT_LANGUAGE:-haskell}"
FLAKE_PATH="${INPUT_FLAKE_PATH:-.}"
OWNER_REGEX="${INPUT_OWNER_REGEX:-}"
OUTPUT="${INPUT_OUTPUT:-docs/dependencies.md}"
TITLE="${INPUT_TITLE:-Dependency Graph}"
STALENESS="${INPUT_STALENESS:-true}"

# Resolve the action root whether invoked via $ACTION_PATH or directly.
if [ -n "${ACTION_PATH:-}" ]; then
  SCRIPT_DIR="$ACTION_PATH/scripts"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [ -z "$OWNER_REGEX" ]; then
  echo "::error::dep-graph: 'owner-regex' input is required" >&2
  exit 1
fi

case "$LANGUAGE" in
  haskell) EXTRACTOR="$SCRIPT_DIR/haskell.clj" ;;
  *)
    echo "::error::dep-graph: unsupported language '$LANGUAGE' (supported: haskell)" >&2
    exit 1
    ;;
esac

bb_args=("$EXTRACTOR" "$FLAKE_PATH" "$OWNER_REGEX" "--title" "$TITLE")
if [ "$STALENESS" != "true" ]; then
  bb_args+=("--no-staleness")
fi

render() {
  if command -v bb >/dev/null 2>&1 \
    && command -v gh >/dev/null 2>&1 \
    && command -v jq >/dev/null 2>&1; then
    bb "${bb_args[@]}"
  else
    nix --extra-experimental-features 'nix-command flakes' shell \
      nixpkgs#babashka nixpkgs#gh nixpkgs#jq nixpkgs#git nixpkgs#coreutils \
      --command bb "${bb_args[@]}"
  fi
}

if [ "$OUTPUT" = "-" ]; then
  render
  exit 0
fi

mkdir -p "$(dirname "$OUTPUT")"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
render >"$tmp"
mv "$tmp" "$OUTPUT"
echo "dep-graph: wrote $OUTPUT ($(wc -l <"$OUTPUT") lines)" >&2

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "path=$OUTPUT" >>"$GITHUB_OUTPUT"
fi
