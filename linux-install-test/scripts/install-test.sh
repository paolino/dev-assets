#!/usr/bin/env bash
# The artifacts as a user meets them: the DEB installed with apt on Ubuntu,
# the RPM with rpm on Fedora, each AppImage run as a file, every one in a
# container that has no /nix, and every command of the product run from the
# path the package put it on. An extraction smoke runs a program on a machine
# that already holds its store paths; this does not.
set -euo pipefail

fail() {
  echo "linux-install-test: FAIL $*" >&2
  exit 1
}
command -v docker >/dev/null 2>&1 || fail "needs docker on the runner"
for name in INPUT_ARTIFACTS_DIR INPUT_ARTIFACT_VERSION INPUT_EXECUTABLE_NAME; do
  [ -n "${!name:-}" ] || fail "needs $name"
done

dir="$(cd "$INPUT_ARTIFACTS_DIR" && pwd -P)"
exe="$INPUT_EXECUTABLE_NAME"
system="${INPUT_SYSTEM_SUFFIX:-x86_64-linux}"
base="$exe-$INPUT_ARTIFACT_VERSION-$system"
commands="${INPUT_COMMANDS:-}"
[ -n "$commands" ] || commands="$exe"
ubuntu="${INPUT_UBUNTU_IMAGE:-ubuntu:24.04}"
fedora="${INPUT_FEDORA_IMAGE:-fedora:41}"

# what runs inside each container, given the commands' paths
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cat >"$work/run-commands.sh" <<'INNER'
#!/usr/bin/env bash
# usage: run-commands.sh COMMAND_PATH...   (COMMANDS_ARGS and USAGE_GREP from the environment)
set -euo pipefail
read -ra args <<< "${COMMANDS_ARGS:-}"
for command in "$@"; do
  output="$("$command" ${args[@]+"${args[@]}"} 2>&1 || true)"
  printf '%s: %s\n' "$command" "$(printf '%s' "$output" | head -n 1)"
  if [ -n "${USAGE_GREP:-}" ] && ! grep -qF -- "$USAGE_GREP" <<<"$output"; then
    echo "linux-install-test: FAIL $command printed no [$USAGE_GREP]" >&2
    exit 1
  fi
done
INNER
chmod +x "$work/run-commands.sh"

IFS=',' read -ra wanted_commands <<< "$commands"
artifacts="${INPUT_ARTIFACTS:-appimage,deb,rpm}"
IFS=',' read -ra wanted <<< "$artifacts"
on_path=()
for command in "${wanted_commands[@]}"; do on_path+=("/usr/bin/$command"); done
run=(docker run --rm -e COMMANDS_ARGS="${INPUT_SMOKE_ARGS:-}" -e USAGE_GREP="${INPUT_USAGE_GREP:-}"
  -v "$dir:/artifacts:ro" -v "$work:/test:ro")

for artifact in "${wanted[@]}"; do
  case "$artifact" in
    deb)
      [ -f "$dir/$base.deb" ] || fail "no $base.deb in $dir"
      "${run[@]}" "$ubuntu" bash -c "
        set -euo pipefail
        [ ! -e /nix ] || { echo 'the image already has /nix' >&2; exit 1; }
        apt-get install -y -q /artifacts/$base.deb > /tmp/apt.log 2>&1 || { tail -n 20 /tmp/apt.log >&2; exit 1; }
        /test/run-commands.sh ${on_path[*]}
      " || fail "the DEB does not install and run on $ubuntu"
      echo "linux-install-test: deb installed on $ubuntu; ${commands} run"
      ;;
    rpm)
      [ -f "$dir/$base.rpm" ] || fail "no $base.rpm in $dir"
      "${run[@]}" "$fedora" bash -c "
        set -euo pipefail
        [ ! -e /nix ] || { echo 'the image already has /nix' >&2; exit 1; }
        rpm -i /artifacts/$base.rpm
        /test/run-commands.sh ${on_path[*]}
      " || fail "the RPM does not install and run on $fedora"
      echo "linux-install-test: rpm installed on $fedora; ${commands} run"
      ;;
    appimage)
      for command in "${wanted_commands[@]}"; do
        image="$command-$INPUT_ARTIFACT_VERSION-$system.AppImage"
        [ -f "$dir/$image" ] || fail "no $image in $dir"
        # an AppImage mounts itself (FUSE) and maps its store (user
        # namespaces), which a desktop allows and a default container does not
        "${run[@]}" --privileged "$ubuntu" bash -c "
          set -euo pipefail
          [ ! -e /nix ] || { echo 'the image already has /nix' >&2; exit 1; }
          cp /artifacts/$image /tmp/$command
          chmod +x /tmp/$command
          /test/run-commands.sh /tmp/$command
        " || fail "the AppImage $image does not run on $ubuntu"
      done
      echo "linux-install-test: AppImages of ${commands} run on $ubuntu"
      ;;
    *) fail "unknown artifact $artifact" ;;
  esac
done
echo "linux-install-test: OK ($artifacts; $commands)"
