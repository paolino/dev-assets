#!/usr/bin/env bash
set -euo pipefail

# Integration test for linux-release/scripts/build.sh.
#
# The composite action's build step orchestrates a Nix build, a Nix
# smoke run, and a staged copy into ./artifacts. Real Nix would
# require a populated store; instead, this test PATH-shims `nix` so
# `nix build` produces a fixture symlink and `nix run` records its
# argv. Every other primitive is real bash + real filesystem.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
build_script="$repo_root/linux-release/scripts/build.sh"

tmp="$(mktemp -d)"
cleanup() {
  chmod -R u+w "$tmp" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

fixture_dir="$tmp/fixture-artifacts"
mkdir -p "$fixture_dir"
printf 'appimage\n' >"$fixture_dir/foo-0.0.1.AppImage"
printf 'deb\n'      >"$fixture_dir/foo-0.0.1.deb"
printf 'rpm\n'      >"$fixture_dir/foo-0.0.1.rpm"
printf 'musl\n'     >"$fixture_dir/foo-0.0.1-musl.tar.gz"
printf 'sums\n'     >"$fixture_dir/SHA256SUMS"

shim_dir="$tmp/bin"
mkdir -p "$shim_dir"
cat >"$shim_dir/nix" <<'NIXSHIM'
#!/usr/bin/env bash
set -euo pipefail

log="${NIX_SHIM_LOG:-/dev/null}"
printf 'nix' >>"$log"
for a in "$@"; do printf ' %q' "$a" >>"$log"; done
printf '\n' >>"$log"

filtered=()
for a in "$@"; do
  case "$a" in
    --quiet|--print-out-paths) ;;
    *) filtered+=("$a") ;;
  esac
done
set -- "${filtered[@]}"

sub="${1:-}"
shift || true
case "$sub" in
  build)
    out_link=""
    target=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --out-link) out_link="$2"; shift 2 ;;
        *) target="$1"; shift ;;
      esac
    done
    if [ -z "$out_link" ] || [ -z "$target" ]; then
      echo "nix-shim: missing --out-link or target (got: $*)" >&2
      exit 1
    fi
    ln -sfn "${NIX_SHIM_FIXTURE:?NIX_SHIM_FIXTURE not set}" "$out_link"
    printf '%s\n' "$NIX_SHIM_FIXTURE"
    ;;
  run)
    # ".#smoke-app" -- <args>
    [ $# -gt 0 ] || { echo "nix-shim run: missing target" >&2; exit 1; }
    shift
    [ "${1:-}" = "--" ] && shift
    saw_artifacts_dir=0
    saw_artifact_version=0
    saw_executable_name=0
    saw_usage_grep=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --artifacts-dir)     saw_artifacts_dir=1; shift 2 ;;
        --artifact-version)  saw_artifact_version=1; shift 2 ;;
        --executable-name)   saw_executable_name=1; shift 2 ;;
        --usage-grep)        saw_usage_grep=1; shift 2 ;;
        *) shift ;;
      esac
    done
    if [ $saw_artifacts_dir -ne 1 ] \
       || [ $saw_artifact_version -ne 1 ] \
       || [ $saw_executable_name -ne 1 ] \
       || [ $saw_usage_grep -ne 1 ]; then
      echo "nix-shim run: smoke app missing one of --artifacts-dir/--artifact-version/--executable-name/--usage-grep" >&2
      exit 1
    fi
    ;;
  shell)
    # publish-release.sh path; not under test here.
    echo "nix-shim: shell subcommand not used in build-dispatch test" >&2
    exit 1
    ;;
  *)
    echo "nix-shim: unsupported subcommand '$sub'" >&2
    exit 1
    ;;
esac
NIXSHIM
chmod +x "$shim_dir/nix"

export NIX_SHIM_FIXTURE="$fixture_dir"
export NIX_SHIM_LOG="$tmp/nix-shim.log"
: >"$NIX_SHIM_LOG"

workspace="$tmp/workspace"
mkdir -p "$workspace"
(
  cd "$workspace"
  git init --quiet
  git config user.email test@example.invalid
  git config user.name 'Test User'
  git commit --quiet --allow-empty -m 'init'
)
short_sha="$(cd "$workspace" && git rev-parse --short=7 HEAD)"

run_build() {
  local outfile="$1"; shift
  local logfile="$1"; shift
  (
    cd "$workspace"
    env \
      PATH="$shim_dir:$PATH" \
      ACTION_PATH="$repo_root/linux-release" \
      RUNNER_TEMP="$tmp" \
      GITHUB_OUTPUT="$outfile" \
      "$@" \
      bash "$build_script"
  ) >"$logfile" 2>&1
}

# ---------------------------------------------------------------------------
# Case 1: happy-path release mode.
# ---------------------------------------------------------------------------
out1="$tmp/github-output.release"
: >"$out1"
run_build "$out1" "$tmp/release.log" \
  INPUT_MODE=release \
  INPUT_TAG=v0.0.1 \
  INPUT_EXECUTABLE_NAME=foo \
  INPUT_USAGE_GREP=Usage: \
  INPUT_RELEASE_OUTPUT=foo-linux-release-artifacts \
  INPUT_DEV_OUTPUT=foo-linux-dev-release-artifacts \
  INPUT_RELEASE_VERSION_COMMAND='echo 0.0.1' \
  INPUT_ARTIFACT_NAME_PREFIX=linux-release-bundles \
  INPUT_DEV_ARTIFACT_NAME_PREFIX=linux-dev-release-bundles \
  INPUT_SMOKE_APP=linux-artifact-smoke

grep -q '^artifact_version=0\.0\.1$' "$out1" \
  || { echo "release: artifact_version missing/wrong" >&2; cat "$out1" >&2; exit 1; }
grep -q '^artifact_name=linux-release-bundles-foo$' "$out1" \
  || { echo "release: artifact_name missing/wrong" >&2; cat "$out1" >&2; exit 1; }
grep -q '^artifacts_dir=' "$out1" \
  || { echo "release: artifacts_dir missing" >&2; cat "$out1" >&2; exit 1; }
test -d "$workspace/artifacts" \
  || { echo "release: artifacts/ not created" >&2; exit 1; }
test -f "$workspace/artifacts/foo-0.0.1.AppImage" \
  || { echo "release: AppImage not copied" >&2; exit 1; }
test -f "$workspace/artifacts/foo-0.0.1-musl.tar.gz" \
  || { echo "release: musl tarball not copied" >&2; exit 1; }
test -f "$workspace/artifacts/SHA256SUMS" \
  || { echo "release: SHA256SUMS not copied" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Case 2: happy-path dev-linux mode (short-sha suffix on the version).
# ---------------------------------------------------------------------------
out2="$tmp/github-output.dev"
: >"$out2"
run_build "$out2" "$tmp/dev.log" \
  INPUT_MODE=dev-linux \
  INPUT_TAG=ignored \
  INPUT_EXECUTABLE_NAME=foo \
  INPUT_USAGE_GREP=Usage: \
  INPUT_RELEASE_OUTPUT=foo-linux-release-artifacts \
  INPUT_DEV_OUTPUT=foo-linux-dev-release-artifacts \
  INPUT_RELEASE_VERSION_COMMAND='echo 0.0.1' \
  INPUT_ARTIFACT_NAME_PREFIX=linux-release-bundles \
  INPUT_DEV_ARTIFACT_NAME_PREFIX=linux-dev-release-bundles \
  INPUT_SMOKE_APP=linux-artifact-smoke

grep -q "^artifact_version=0\.0\.1-${short_sha}$" "$out2" \
  || { echo "dev-linux: artifact_version did not gain short-sha suffix" >&2; cat "$out2" >&2; exit 1; }
grep -q '^artifact_name=linux-dev-release-bundles-foo$' "$out2" \
  || { echo "dev-linux: artifact_name wrong" >&2; cat "$out2" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Case 3: input validation error paths.
# ---------------------------------------------------------------------------
expect_fail() {
  local label="$1"; shift
  local expected_msg="$1"; shift
  local errlog="$tmp/${label}.err"
  if run_build "$tmp/${label}.out" "$errlog" "$@"; then
    echo "$label: expected non-zero exit but got 0" >&2
    cat "$errlog" >&2
    exit 1
  fi
  grep -q "$expected_msg" "$errlog" \
    || { echo "$label: expected stderr to contain '$expected_msg'" >&2; cat "$errlog" >&2; exit 1; }
}

expect_fail missing-exe 'executable-name is required' \
  INPUT_MODE=release \
  INPUT_TAG=v0.0.1 \
  INPUT_USAGE_GREP=Usage: \
  INPUT_RELEASE_OUTPUT=foo-linux-release-artifacts \
  INPUT_DEV_OUTPUT=foo-linux-dev-release-artifacts \
  INPUT_RELEASE_VERSION_COMMAND='echo 0.0.1'

expect_fail missing-grep 'usage-grep is required' \
  INPUT_MODE=release \
  INPUT_TAG=v0.0.1 \
  INPUT_EXECUTABLE_NAME=foo \
  INPUT_RELEASE_OUTPUT=foo-linux-release-artifacts \
  INPUT_DEV_OUTPUT=foo-linux-dev-release-artifacts \
  INPUT_RELEASE_VERSION_COMMAND='echo 0.0.1'

expect_fail missing-version 'release-version-command is required' \
  INPUT_MODE=release \
  INPUT_TAG=v0.0.1 \
  INPUT_EXECUTABLE_NAME=foo \
  INPUT_USAGE_GREP=Usage: \
  INPUT_RELEASE_OUTPUT=foo-linux-release-artifacts \
  INPUT_DEV_OUTPUT=foo-linux-dev-release-artifacts

expect_fail missing-tag 'release mode requires a tag' \
  INPUT_MODE=release \
  INPUT_TAG= \
  INPUT_EXECUTABLE_NAME=foo \
  INPUT_USAGE_GREP=Usage: \
  INPUT_RELEASE_OUTPUT=foo-linux-release-artifacts \
  INPUT_DEV_OUTPUT=foo-linux-dev-release-artifacts \
  INPUT_RELEASE_VERSION_COMMAND='echo 0.0.1'

expect_fail bad-mode 'unsupported Linux release mode: bogus' \
  INPUT_MODE=bogus \
  INPUT_EXECUTABLE_NAME=foo \
  INPUT_USAGE_GREP=Usage: \
  INPUT_RELEASE_OUTPUT=foo-linux-release-artifacts \
  INPUT_DEV_OUTPUT=foo-linux-dev-release-artifacts \
  INPUT_RELEASE_VERSION_COMMAND='echo 0.0.1'

echo "build-dispatch: OK"
