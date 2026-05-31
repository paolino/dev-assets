# Generalized Linux artifact smoke harness. Extracts each artifact from its
# packaged form and runs the executable, requiring an optional substring in its
# combined (stdout+stderr) no-args output. The artifact set defaults to the full
# symmetric matrix (AppImage/DEB/RPM/musl on both arches) and can be overridden
# with --artifacts.
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

    Extracts each artifact and runs NAME, requiring its combined no-args
    output to contain --usage-grep (when given).
    USAGE
    }

    artifacts_dir=""
    artifact_version=""
    system_suffix="${system}"
    executable_name=""
    usage_grep=""
    artifacts="${defaultArtifacts}"

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --artifacts-dir) artifacts_dir="$2"; shift 2;;
        --artifact-version) artifact_version="$2"; shift 2;;
        --system-suffix) system_suffix="$2"; shift 2;;
        --executable-name) executable_name="$2"; shift 2;;
        --usage-grep) usage_grep="$2"; shift 2;;
        --artifacts) artifacts="$2"; shift 2;;
        -h|--help) usage; exit 0;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 2;;
      esac
    done

    if [ -z "$artifacts_dir" ] || [ -z "$artifact_version" ] || [ -z "$executable_name" ]; then
      usage >&2
      exit 2
    fi

    artifacts_dir="$(cd "$artifacts_dir" && pwd)"
    workdir="$(mktemp -d)"
    trap 'rm -rf "$workdir"' EXIT

    base="$executable_name-$artifact_version-$system_suffix"

    smoke_cli() {
      bin="$1"
      test -x "$bin"
      output="$("$bin" 2>&1 || true)"
      printf '%s\n' "$output"
      if [ -n "$usage_grep" ]; then
        grep -F -- "$usage_grep" <<<"$output" >/dev/null
      fi
    }

    smoke_appimage() {
      appimage="$artifacts_dir/$base.AppImage"
      test -f "$appimage"
      dir="$workdir/appimage"
      mkdir -p "$dir"
      cp -L "$appimage" "$dir/$executable_name.AppImage"
      chmod +x "$dir/$executable_name.AppImage"
      ( cd "$dir" && "./$executable_name.AppImage" --appimage-extract >/dev/null )
      smoke_cli "$(find "$dir" -name "$executable_name" -type f -executable | head -1)"
    }

    smoke_deb() {
      deb="$artifacts_dir/$base.deb"
      test -f "$deb"
      dir="$workdir/deb"
      mkdir -p "$dir"
      dpkg-deb -x "$deb" "$dir"
      smoke_cli "$(find "$dir" -name "$executable_name" -type f -executable | head -1)"
    }

    smoke_rpm() {
      rpm="$artifacts_dir/$base.rpm"
      test -f "$rpm"
      dir="$workdir/rpm"
      mkdir -p "$dir"
      ( cd "$dir" && rpm2cpio "$rpm" | cpio -idm >/dev/null 2>&1 )
      smoke_cli "$(find "$dir" -name "$executable_name" -type f -executable | head -1)"
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

    echo "linux-artifact-smoke: OK ($artifacts)"
  '';
}
