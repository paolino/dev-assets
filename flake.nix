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
        glibcArtifacts =
          if system == "aarch64-linux"
          then [ "appimage" ]
          else [ "appimage" "deb" "rpm" ];
        # GHC-free self-test: prove the lib without dragging haskell.nix in.
        selfTest = lib.mkLinuxBundle {
          inherit pkgs system bundlers;
          executableName = "hello";
          version = "2.12.1";
          package = pkgs.hello;
          artifacts = glibcArtifacts;
        };
        selfTestMusl = lib.mkMuslTarball {
          inherit pkgs system;
          executableName = "hello";
          version = "2.12.1";
          package = pkgs.pkgsStatic.hello;
        };
      in
      {
        packages.self-test = selfTest;
        packages.self-test-musl = selfTestMusl;
      });
}
