# Compose the glibc bundle + musl tarball for one executable on one system into
# a single staged directory with a combined SHA256SUMS. This is the per-exe
# release artifact a consumer exposes as its `<exe>-linux-release-artifacts`.
{ pkgs
, system
, executableName
, version
, artifactVersion ? version
, glibcPackage
, muslPackage
, bundlers
, glibcArtifacts ? (
    if system == "aarch64-linux"
    then [ "appimage" ]
    else [ "appimage" "deb" "rpm" ]
  )
}:
let
  glibc = import ./mk-linux-bundle.nix {
    inherit pkgs system executableName version artifactVersion bundlers;
    package = glibcPackage;
    artifacts = glibcArtifacts;
  };
  musl = import ./mk-musl-tarball.nix {
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
  cp -L ${musl}/* "$out"/
  ( cd "$out" && sha256sum -- * > SHA256SUMS )
''
