# Package a statically-linked (musl) executable as a .tar.gz. `package` must be
# a static build — e.g. pkgsStatic.<pkg>, or a haskell.nix
# *-multiplatform-musl cross exe. The binary is copied flat into the archive;
# the combined SHA256SUMS is written by mk-linux-artifacts when composing.
{ pkgs
, system
, executableName
, version
, artifactVersion ? version
, package
}:
let
  base = "${executableName}-${artifactVersion}-${system}-musl";
in
pkgs.runCommand "${executableName}-${artifactVersion}-${system}-musl-artifacts"
  {
    nativeBuildInputs = [ pkgs.coreutils pkgs.gnutar pkgs.gzip ];
    passthru = { inherit package; };
  } ''
  mkdir -p "$out" staging
  cp -L "${package}/bin/${executableName}" "staging/${executableName}"
  chmod +w "staging/${executableName}"
  tar -C staging --owner=0 --group=0 -czf "$out/${base}.tar.gz" "${executableName}"
''
