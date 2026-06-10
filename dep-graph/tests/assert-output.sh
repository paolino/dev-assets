#!/usr/bin/env bash
# Assert a generated dependency-graph document has the expected shape.
# Usage: assert-output.sh <markdown-file> [expected-title]
set -euo pipefail

file="${1:?usage: assert-output.sh <markdown-file> [expected-title]}"
expected_title="${2:-}"

if [ ! -s "$file" ]; then
  echo "assert-output: '$file' is missing or empty" >&2
  exit 1
fi

fail=0
need() {
  if ! grep -qF -- "$1" "$file"; then
    echo "assert-output: expected to find: $1" >&2
    fail=1
  fi
}

need '## Repositories'
need '## Diagram'
need '```mermaid'
need 'graph TD'

if [ -n "$expected_title" ]; then
  need "# $expected_title"
fi

if [ "$fail" -ne 0 ]; then
  echo "assert-output: FAILED for $file" >&2
  exit 1
fi

echo "assert-output: OK ($file, $(wc -l <"$file") lines)"
