# Generalized Linux artifact smoke harness. Extracts each artifact from its
# packaged form and runs the executable, requiring an optional substring in its
# combined (stdout+stderr) output. The artifact set defaults to the full
# symmetric matrix (AppImage/DEB/RPM/musl on both arches) and can be overridden
# with --artifacts.
#
# The program run is the one the artifact itself names: the AppImage's
# `entrypoint`, the package's `usr/bin/<command>` or `bin/<command>` link,
# followed inside the extracted tree. A search by file name is only the
# fallback, because a closure can hold two files of one name (a wrapper and the
# program it wraps). `--commands` smokes several commands of one product (one
# AppImage per command, one DEB and one RPM for all; see mk-linux-bundle.nix),
# and `--smoke-args` runs each with arguments instead of none, for a program
# whose no-argument run does something else than print its usage.
{ pkgs
, system
, artifacts ? [ "appimage" "deb" "rpm" "musl" ]
}:
let
  defaultArtifacts = builtins.concatStringsSep "," artifacts;
in
pkgs.writeShellApplication {
  name = "linux-artifact-smoke";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.findutils
    pkgs.gnugrep
    pkgs.gnutar
    pkgs.gzip
    pkgs.dpkg
    pkgs.rpm
    pkgs.cpio
  ];
  text = ''
    set -euo pipefail

    usage() {
      cat <<'USAGE'
    Usage: linux-artifact-smoke
        --artifacts-dir DIR
        --artifact-version VERSION
        --executable-name NAME
        [--system-suffix SYSTEM]
        [--usage-grep STRING]
        [--artifacts a,b,c]   (subset of: appimage,deb,rpm,musl)
        [--commands a,b,c]    (the product's commands; default: NAME)
        [--smoke-args "ARGS"] (arguments each command runs with; default: none)

    Extracts each artifact and runs each command, requiring its combined
    output to contain --usage-grep (when given).
    USAGE
    }

    artifacts_dir=""
    artifact_version=""
    system_suffix="${system}"
    executable_name=""
    usage_grep=""
    artifacts="${defaultArtifacts}"
    commands=""
    smoke_args=""

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --artifacts-dir) artifacts_dir="$2"; shift 2;;
        --artifact-version) artifact_version="$2"; shift 2;;
        --system-suffix) system_suffix="$2"; shift 2;;
        --executable-name) executable_name="$2"; shift 2;;
        --usage-grep) usage_grep="$2"; shift 2;;
        --artifacts) artifacts="$2"; shift 2;;
        --commands) commands="$2"; shift 2;;
        --smoke-args) smoke_args="$2"; shift 2;;
        -h|--help) usage; exit 0;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 2;;
      esac
    done

    if [ -z "$artifacts_dir" ] || [ -z "$artifact_version" ] || [ -z "$executable_name" ]; then
      usage >&2
      exit 2
    fi
    [ -n "$commands" ] || commands="$executable_name"
    IFS=',' read -ra wanted_commands <<< "$commands"
    read -ra args <<< "$smoke_args"

    artifacts_dir="$(cd "$artifacts_dir" && pwd)"
    workdir="$(mktemp -d)"
    trap 'rm -rf "$workdir"' EXIT

    base="$executable_name-$artifact_version-$system_suffix"

    # resolve ROOT PATH: follow PATH while it is a link, an absolute target
    # read inside ROOT (the extracted tree stands for the store)
    resolve() {
      local root="$1" path="$2" target hops=0
      while [ -L "$path" ] && [ "$hops" -lt 40 ]; do
        target="$(readlink "$path")"
        case "$target" in
          /*) path="$root$target" ;;
          *) path="$(dirname "$path")/$target" ;;
        esac
        hops=$((hops + 1))
      done
      printf '%s' "$path"
    }

    # program_in ROOT COMMAND [LINK...]: the file the first existing LINK names,
    # or the fallback search by name
    program_in() {
      local root="$1" command="$2" link
      shift 2
      for link in "$@"; do
        if [ -e "$link" ] || [ -L "$link" ]; then
          resolve "$root" "$link"
          return
        fi
      done
      find "$root" -name "$command" -type f -executable | head -1
    }

    smoke_cli() {
      bin="$1"
      test -x "$bin"
      output="$("$bin" ''${args[@]+"''${args[@]}"} 2>&1 || true)"
      printf '%s\n' "$output"
      if [ -n "$usage_grep" ]; then
        grep -F -- "$usage_grep" <<<"$output" >/dev/null
      fi
    }

    smoke_appimage() {
      for command in "''${wanted_commands[@]}"; do
        appimage="$artifacts_dir/$command-$artifact_version-$system_suffix.AppImage"
        test -f "$appimage"
        dir="$workdir/appimage-$command"
        mkdir -p "$dir"
        cp -L "$appimage" "$dir/$command.AppImage"
        chmod +x "$dir/$command.AppImage"
        ( cd "$dir" && "./$command.AppImage" --appimage-extract >/dev/null )
        smoke_cli "$(program_in "$dir/squashfs-root" "$command" "$dir/squashfs-root/entrypoint")"
      done
    }

    smoke_package() {
      dir="$1"
      for command in "''${wanted_commands[@]}"; do
        smoke_cli "$(program_in "$dir" "$command" "$dir/usr/bin/$command" "$dir/bin/$command")"
      done
    }

    smoke_deb() {
      deb="$artifacts_dir/$base.deb"
      test -f "$deb"
      dir="$workdir/deb"
      mkdir -p "$dir"
      dpkg-deb -x "$deb" "$dir"
      smoke_package "$dir"
    }

    smoke_rpm() {
      rpm="$artifacts_dir/$base.rpm"
      test -f "$rpm"
      dir="$workdir/rpm"
      mkdir -p "$dir"
      ( cd "$dir" && rpm2cpio "$rpm" | cpio -idm >/dev/null 2>&1 )
      smoke_package "$dir"
    }

    smoke_musl() {
      tarball="$artifacts_dir/$base-musl.tar.gz"
      test -f "$tarball"
      dir="$workdir/musl"
      mkdir -p "$dir"
      tar -C "$dir" -xzf "$tarball"
      smoke_cli "$(find "$dir" -name "$executable_name" -type f -executable | head -1)"
    }

    reject_duplicate_appimage() {
      duplicate="$artifacts_dir/$executable_name.AppImage"
      if [ -e "$duplicate" ]; then
        echo "unexpected duplicate AppImage asset: $duplicate" >&2
        exit 1
      fi
    }

    reject_duplicate_appimage
    IFS=',' read -ra wanted <<< "$artifacts"
    for a in "''${wanted[@]}"; do
      case "$a" in
        appimage) smoke_appimage;;
        deb) smoke_deb;;
        rpm) smoke_rpm;;
        musl) smoke_musl;;
        *) echo "unknown artifact: $a" >&2; exit 2;;
      esac
    done

    echo "linux-artifact-smoke: OK ($artifacts; $commands)"
  '';
}
