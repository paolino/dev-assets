{
  description = "Shared development and release assets";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    bundlers = {
      url = "github:NixOS/bundlers";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, bundlers }:
    let
      lib = import ./nix/lib;
    in
    { inherit lib; }
    // flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        glibcArtifacts = [ "appimage" "deb" "rpm" ];
        # GHC-free self-test: prove the lib without dragging haskell.nix in.
        # The full per-exe matrix: glibc bundle + musl tarball + SHA256SUMS.
        selfTest = lib.mkLinuxArtifacts {
          inherit pkgs system bundlers;
          executableName = "hello";
          version = "2.12.1";
          glibcPackage = pkgs.hello;
          muslPackage = pkgs.pkgsStatic.hello;
          glibcArtifacts = glibcArtifacts;
        };
        selfTestSmokeHarness = lib.mkLinuxArtifactSmoke { inherit pkgs system; };
        selfTestSmoke = pkgs.writeShellApplication {
          name = "self-test-smoke";
          runtimeInputs = [ selfTestSmokeHarness ];
          text = ''
            linux-artifact-smoke \
              --artifacts-dir ${selfTest} \
              --artifact-version 2.12.1 \
              --executable-name hello \
              --usage-grep "Hello, world!"
          '';
        };
      in
      {
        packages.self-test = selfTest;
        packages.self-test-smoke = selfTestSmoke;
      });
}
