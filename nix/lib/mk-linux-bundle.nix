# Build a configurable set of glibc Linux artifacts (AppImage / DEB / RPM) for
# one package on one system, via NixOS/bundlers. Generalized from the
# linux-release.nix that consumers used to copy. aarch64 callers typically pass
# `artifacts = [ "appimage" ]` (DEB/RPM are x86_64-only in our matrix).
{ pkgs
, system
, executableName
, version
, artifactVersion ? version
, package
, bundlers
, artifacts ? [ "appimage" "deb" "rpm" ]
}:
let
  lib = pkgs.lib;
  want = name: builtins.elem name artifacts;
  appImage = bundlers.bundlers.${system}.toAppImage package;
  deb = bundlers.bundlers.${system}.toDEB package;
  rpm = bundlers.bundlers.${system}.toRPM package;
  base = "${executableName}-${artifactVersion}-${system}";
in
pkgs.runCommand "${executableName}-${artifactVersion}-${system}-glibc-artifacts"
  {
    nativeBuildInputs = [ pkgs.coreutils pkgs.findutils ];
    passthru = { inherit appImage deb rpm; };
  } ''
  mkdir -p "$out"
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
''
