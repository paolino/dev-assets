# Build a configurable set of glibc Linux artifacts (AppImage / DEB / RPM) for
# one package on one system, via NixOS/bundlers. Generalized from the
# linux-release.nix that consumers used to copy. aarch64 callers typically pass
# `artifacts = [ "appimage" ]` (DEB/RPM are x86_64-only in our matrix).
#
# `commands` lists the package's commands a user installs. With one command
# (the default, `executableName`) the artifacts are the bundlers' own. With
# several, every command gets its own AppImage (`<command>-<version>-<system>`)
# and the product gets one DEB and one RPM (`<executableName>-<version>-<system>`)
# that link every command into /usr/bin (mk-closure-packages.nix): the
# bundlers' per-program packages of one product share store paths and cannot
# be installed together.
{ pkgs
, system
, executableName
, version
, artifactVersion ? version
, package
, bundlers
, artifacts ? [ "appimage" "deb" "rpm" ]
, commands ? [ executableName ]
}:
let
  lib = pkgs.lib;
  want = name: builtins.elem name artifacts;
  multi = commands != [ executableName ];
  base = "${executableName}-${artifactVersion}-${system}";
  # the package with one command as its main program, for the AppImage of it
  withMain = command: pkgs.symlinkJoin {
    name = "${command}-${artifactVersion}";
    paths = [ package ];
    meta.mainProgram = command;
  };
  appImageOf = command: bundlers.bundlers.${system}.toAppImage (withMain command);
  appImage = bundlers.bundlers.${system}.toAppImage package;
  deb = bundlers.bundlers.${system}.toDEB package;
  rpm = bundlers.bundlers.${system}.toRPM package;
  closurePackages = import ./mk-closure-packages.nix {
    inherit pkgs package commands;
    name = executableName;
    version = artifactVersion;
    formats = builtins.filter want [ "deb" "rpm" ];
  };
  singleCommand = ''
    ${lib.optionalString (want "appimage") ''
      cp -L ${appImage} "$out/${base}.AppImage"
    ''}
    ${lib.optionalString (want "deb") ''
      deb_file="$(find ${deb} -maxdepth 1 -type f -name '*.deb' | head -1)"
      test -n "$deb_file"
      cp "$deb_file" "$out/${base}.deb"
    ''}
    ${lib.optionalString (want "rpm") ''
      rpm_file="$(find ${rpm} -maxdepth 1 -type f -name '*.rpm' | head -1)"
      test -n "$rpm_file"
      cp "$rpm_file" "$out/${base}.rpm"
    ''}
  '';
  severalCommands = ''
    ${lib.optionalString (want "appimage") (lib.concatMapStringsSep "\n"
      (command: ''cp -L ${appImageOf command} "$out/${command}-${artifactVersion}-${system}.AppImage"'')
      commands)}
    ${lib.optionalString (want "deb") ''
      cp ${closurePackages}/${executableName}.deb "$out/${base}.deb"
    ''}
    ${lib.optionalString (want "rpm") ''
      cp ${closurePackages}/${executableName}.rpm "$out/${base}.rpm"
    ''}
  '';
in
pkgs.runCommand "${executableName}-${artifactVersion}-${system}-glibc-artifacts"
  {
    nativeBuildInputs = [ pkgs.coreutils pkgs.findutils ];
    passthru = { inherit appImage deb rpm commands; } // lib.optionalAttrs multi { inherit closurePackages; };
  } ''
  mkdir -p "$out"
  ${if multi then severalCommands else singleCommand}
''
