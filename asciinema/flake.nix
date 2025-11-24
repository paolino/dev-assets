{
  description = "python scripts to fix type casts";

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
          compress = pkgs.writers.writePython3Bin "compress" {
            flakeIgnore = [
              "E501"
              "E402"
              "E265"
              "W292"
            ];
          } (builtins.readFile ./compress.py);
          resize = pkgs.writers.writePython3Bin "resize" {
            flakeIgnore = [
              "E501"
              "E402"
              "E265"
              "W292"
            ];
          } (builtins.readFile ./resize.py);
        in
        {
          packages.compress = compress;
          packages.resize = resize;
          devShells.default = pkgs.mkShell {
            packages = [
              resize
              compress
              pkgs.asciinema
            ];

            shellHook = ''
              echo "MkDocs environment ready!"
              echo "Run: mkdocs serve"
            '';
          };
        };
    };
}
