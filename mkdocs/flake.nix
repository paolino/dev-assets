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
          # Only override the one that fails (tests break on Python 3.13 due to click.testing I/O edge case)
          swagger-ui-tag-fixed = pkgs.python3Packages.mkdocs-swagger-ui-tag.overridePythonAttrs (old: {
            doCheck = false; # Skips the failing pytest suite — plugin works fine without it
          });
          # Wrapper that cleans up site/ after gh-deploy to prevent
          # read-only files from blocking subsequent CI checkouts
          mkdocs-deploy = pkgs.writeShellScriptBin "mkdocs-deploy" ''
            mkdocs gh-deploy "$@"
            rc=$?
            chmod -R u+w site/ 2>/dev/null
            rm -rf site/
            exit $rc
          '';
          plugins = {
            markdown-graphviz = pkgs.callPackage ./nix/markdown-graphviz.nix { };
            asciinema-plugin = pkgs.callPackage ./nix/asciinema-plugin.nix { };
            markdown-callouts = pkgs.callPackage ./nix/markdown-callouts.nix { };
            static-i18n = pkgs.callPackage ./nix/static-i18n.nix { };
            from-nixpkgs = pkgs.python3.withPackages (ps: [
              ps.mkdocs-material
              ps.mkdocs-mermaid2-plugin
              swagger-ui-tag-fixed
              ps.graphviz
              ps.pymdown-extensions
              ps.mkdocs-macros-plugin
            ]);
          };
          mkdocs-speech = pkgs.writeShellScriptBin "mkdocs-speech" ''
            exec ${pkgs.babashka}/bin/bb ${./bin/mkdocs-speech} "$@"
          '';
        in
        {
          packages = plugins // { inherit mkdocs-speech; };
          devShells.default = pkgs.mkShell {
            packages = [
              pkgs.graphviz
              pkgs.mkdocs
              mkdocs-deploy
              mkdocs-speech
            ]
            ++ (builtins.attrValues plugins);

            shellHook = ''
              echo "MkDocs environment ready!"
              echo "Run: mkdocs serve"
            '';
          };
        };
    };
}
