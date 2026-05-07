#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "::error::$*" >&2
  exit 1
}

write_output() {
  local name="$1"
  local value="$2"

  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "$name" "$value" >>"$GITHUB_OUTPUT"
  fi
}

mode="${INPUT_MODE:-publish}"
source_path="${INPUT_PATH:-site-root}"
preview_root="${INPUT_PREVIEW_ROOT:-/opt/services/previews}"
preview_host="${INPUT_PREVIEW_HOST:-https://preview.dev.plutimus.com}"
owner="${INPUT_OWNER:-${GITHUB_REPOSITORY_OWNER:-}}"
repository="${INPUT_REPOSITORY:-}"
pr_number="${INPUT_PR_NUMBER:-${GITHUB_EVENT_NUMBER:-}}"

if [[ -z "$repository" && -n "${GITHUB_REPOSITORY:-}" ]]; then
  repository="${GITHUB_REPOSITORY#*/}"
fi

case "$mode" in
  publish | cleanup) ;;
  *) fail "Unsupported static preview mode: $mode" ;;
esac

[[ -n "$owner" ]] || fail "Missing preview owner. Set owner or run in a GitHub repository context."
[[ -n "$repository" ]] || fail "Missing preview repository. Set repository or run in a GitHub repository context."
[[ -n "$pr_number" ]] || fail "Missing pull request number. Set pr-number or run from a pull_request event."

preview_root="${preview_root%/}"
preview_host="${preview_host%/}"
preview_owner_dir="$preview_root/$owner"
preview_parent="$preview_owner_dir/$repository"
preview_dir="$preview_parent/pr-$pr_number"
preview_url="$preview_host/$owner/$repository/pr-$pr_number/"
run_id="${GITHUB_RUN_ID:-manual}"
run_attempt="${GITHUB_RUN_ATTEMPT:-1}"

write_output "preview_url" "$preview_url"
write_output "preview_path" "$preview_dir"
write_output "owner" "$owner"
write_output "repository" "$repository"
write_output "pr_number" "$pr_number"

remove_preview_dir() {
  local target="$1"
  local removed_target

  [[ -e "$target" || -L "$target" ]] || return 0

  if rm -rf "$target" 2>/dev/null; then
    return 0
  fi

  removed_target="$target.removed-$run_id-$run_attempt-$$"
  mv "$target" "$removed_target"
  rm -rf "$removed_target" 2>/dev/null || true
}

if [[ "$mode" == "cleanup" ]]; then
  remove_preview_dir "$preview_dir"
  rmdir --ignore-fail-on-non-empty "$preview_parent" 2>/dev/null || true
  rmdir --ignore-fail-on-non-empty "$preview_owner_dir" 2>/dev/null || true
  echo "::notice::Removed static preview $preview_url"
  exit 0
fi

[[ -d "$source_path" ]] || fail "Static preview path does not exist or is not a directory: $source_path"
source_path="$(cd "$source_path" && pwd -P)"

preview_tmp="$preview_dir.tmp-$run_id-$run_attempt-$$"

cleanup_tmp() {
  rm -rf "$preview_tmp"
}
trap cleanup_tmp EXIT

cleanup_old_previews() {
  local old_preview

  for old_preview in "$preview_dir".old-*; do
    [[ -e "$old_preview" || -L "$old_preview" ]] || continue
    rm -rf "$old_preview" 2>/dev/null || true
  done
}

umask 0002
mkdir -p "$preview_parent"
rm -rf "$preview_tmp"
mkdir -p "$preview_tmp"

(cd "$source_path" && find -L . -type d -print) | while IFS= read -r path; do
  mkdir -p "$preview_tmp/$path"
done

(cd "$source_path" && find -L . -type f -print) | while IFS= read -r path; do
  install -m 664 "$source_path/$path" "$preview_tmp/$path"
done

old_preview=""
if [[ -e "$preview_dir" || -L "$preview_dir" ]]; then
  old_preview="$preview_dir.old-$run_id-$run_attempt-$$"
  mv "$preview_dir" "$old_preview"
fi

mv "$preview_tmp" "$preview_dir"
trap - EXIT

cleanup_old_previews

echo "::notice::Published static preview $preview_url"
