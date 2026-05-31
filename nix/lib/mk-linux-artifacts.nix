# Compose the glibc bundle + (optional) musl tarball for one executable on one
# system into a single staged directory with a per-exe/system SHA256SUMS
# (uniquely named so concurrent release uploads don't collide). This is the
# per-exe release artifact a consumer exposes as its
# `<exe>-linux-release-artifacts`. `muslPackage` is optional so a consumer can
# adopt the glibc artifacts first and add musl in a later step.
{ pkgs
, lib ? pkgs.lib
, system
, executableName
, version
, artifactVersion ? version
, glibcPackage
, muslPackage ? null
, bundlers
, glibcArtifacts ? (
    # Symmetric across arches: aarch64 ships DEB/RPM too (NixOS bundlers
    # support them on aarch64-linux). Proven by the arm self-test.
    [ "appimage" "deb" "rpm" ]
  )
}:
let
  glibc = import ./mk-linux-bundle.nix {
    inherit pkgs system executableName version artifactVersion bundlers;
    package = glibcPackage;
    artifacts = glibcArtifacts;
  };
  musl =
    if muslPackage == null
    then null
    else import ./mk-musl-tarball.nix {
      inherit pkgs system executableName version artifactVersion;
      package = muslPackage;
    };
in
pkgs.runCommand "${executableName}-${artifactVersion}-${system}-linux-artifacts"
  {
    nativeBuildInputs = [ pkgs.coreutils ];
    passthru = { inherit glibc musl; };
  } ''
  mkdir -p "$out"
  cp -L ${glibc}/* "$out"/
  ${lib.optionalString (muslPackage != null) ''cp -L ${musl}/* "$out"/''}
  # Per-exe/system checksums name: every release-matrix job uploads its own
  # SHA256SUMS, and a generic name collides on the release (concurrent
  # gh-release-upload race -> HTTP 422). Unique names upload race-free.
  ( cd "$out" && sha256sum -- * > "${executableName}-${artifactVersion}-${system}.SHA256SUMS" )
''
