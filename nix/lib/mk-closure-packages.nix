# DEB and RPM of one package's whole runtime closure, with several of its
# commands linked into /usr/bin. The NixOS bundlers' toDEB/toRPM package one
# program each; two of them built from one product carry the same store paths
# and cannot be installed side by side. A product whose commands are installed
# together (a CLI, its companion, a local node launcher) uses this instead: one
# package, every command on the path, nothing outside /nix/store and /usr/bin.
{ pkgs
, lib ? pkgs.lib
, name
, version
, package
, commands
, formats ? [ "deb" "rpm" ]
}:
let
  closure = pkgs.closureInfo { rootPaths = [ package ]; };
  want = format: builtins.elem format formats;
  linkCommands = lib.concatMapStringsSep "\n"
    (command: ''
      [ -x ${lib.escapeShellArg "${package}/bin/${command}"} ] || {
        echo ${lib.escapeShellArg "mk-closure-packages: ${package} has no bin/${command}"} >&2
        exit 1
      }
      ln -s ${lib.escapeShellArg "${package}/bin/${command}"} root/usr/bin/${lib.escapeShellArg command}
    '')
    commands;
  fpmCommon = "-s dir -n ${lib.escapeShellArg name} -v ${lib.escapeShellArg version} -C root";
in
assert commands != [ ];
pkgs.runCommand "${name}-${version}-closure-packages"
  {
    nativeBuildInputs = [
      pkgs.fpm
      pkgs.rpm
      pkgs.binutils
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnutar
      pkgs.gzip
    ];
    passthru = { inherit closure commands; };
  } ''
  set -euo pipefail
  export HOME="$TMPDIR"
  mkdir -p root/nix/store root/usr/bin "$out"
  while IFS= read -r path; do
    cp -a "$path" root/nix/store/
  done < ${closure}/store-paths
  # the store is read-only; the packager writes inside the copied tree
  chmod -R u+w root/nix/store
  ${linkCommands}
  # every path of the closure is in the package: nothing is read from a store
  # the target machine does not have
  while IFS= read -r path; do
    [ -e "root$path" ] || { echo "mk-closure-packages: $path missing from the package" >&2; exit 1; }
  done < ${closure}/store-paths
  ${lib.optionalString (want "deb") ''
    fpm ${fpmCommon} -t deb --deb-no-default-config-files -p "$out/${name}.deb" nix usr
  ''}
  ${lib.optionalString (want "rpm") ''
    fpm ${fpmCommon} -t rpm --rpm-os linux -p "$out/${name}.rpm" nix usr
  ''}
  ls -l "$out"
''
