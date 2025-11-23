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
          asciinema-plugin = import ./asciinema-plugin.nix { inherit pkgs; };
        in
        {
          packages.mkdocs-asciinema-player = asciinema-plugin;
          devShells.default = pkgs.mkShell {
            packages = [
              asciinema-plugin
              pkgs.mkdocs
            ];

            shellHook = ''
              echo "MkDocs environment ready!"
              echo "Run: mkdocs serve"
            '';
          };
        };
    };
}
