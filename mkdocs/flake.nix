{
  description = "mkdocs shell with plugins";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{
      self,
      flake-parts,
      nixpkgs,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      perSystem =
        { system, pkgs, ... }:
        let
          plugins = {
            asciinema-plugin = pkgs.callPackage ./nix/asciinema-plugin.nix { };
            markdown-callouts = pkgs.callPackage ./nix/markdown-callouts.nix { };
            from-nixpkgs = pkgs.python3.withPackages (ps: [
              ps.mkdocs-material
            ]);
          };
        in
        rec {
          packages = plugins;
          devShells.default = pkgs.mkShell {
            packages = [
              pkgs.mkdocs
            ] ++ (builtins.attrValues plugins);

            shellHook = ''
              echo "MkDocs environment ready!"
              echo "Run: mkdocs serve"
            '';
          };
        };
    };
}
