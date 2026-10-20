# DEB and RPM of one package's whole runtime closure, with several of its
# commands linked into /usr/bin. The NixOS bundlers' toDEB/toRPM package one
# program each; two of them built from one product carry the same store paths
# and cannot be installed side by side. A product whose commands are installed
# together (a CLI, its companion, a local node launcher) uses this instead: one
# package, every command on the path, nothing outside /nix/store and /usr/bin.
#
# `links` adds further links into the package, a path under the package root
# (for example `usr/share/<name>`) to an absolute path inside the closure: the
# data a product's users read beside its commands, at a path they can name.
{ pkgs
, lib ? pkgs.lib
, name
, version
, package
, commands
, formats ? [ "deb" "rpm" ]
, links ? { }
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
  linkData = lib.concatStringsSep "\n" (lib.mapAttrsToList
    (path: target: ''
      [ -e root${lib.escapeShellArg target} ] || {
        echo ${lib.escapeShellArg "mk-closure-packages: the link target ${target} of ${path} is not in the package closure"} >&2
        exit 1
      }
      mkdir -p "root/$(dirname ${lib.escapeShellArg path})"
      ln -s ${lib.escapeShellArg target} root/${lib.escapeShellArg path}
    '')
    links);
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
    passthru = { inherit closure commands links; };
  } ''
  set -euo pipefail
  export HOME="$TMPDIR"
  mkdir -p root/nix/store root/usr/bin "$out"
  # symbolic links stay links; hard links are not kept: the store links equal
  # files of different paths together, and dpkg refuses an archive whose hard
  # links point into another package path it has not unpacked yet
  while IFS= read -r path; do
    cp -R -P --preserve=mode,timestamps "$path" root/nix/store/
  done < ${closure}/store-paths
  # the store is read-only; the packager writes inside the copied tree
  chmod -R u+w root/nix/store
  ${linkCommands}
  ${linkData}
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
