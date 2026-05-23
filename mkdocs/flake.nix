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
          # Theme assets in /nix/store are mode 0444 / 0555. mkdocs uses
          # shutil.copy2 which preserves those bits, leaving the built
          # site/ tree non-writable and blocking subsequent CI checkouts
          # on self-hosted runners. Wrap mkdocs so build/gh-deploy always
          # leave the site dir writable.
          mkdocsFixPerms = ''
            site_dir="site"
            for ((i=1; i<=$#; i++)); do
              case "''${!i}" in
                --site-dir)
                  j=$((i+1)); site_dir="''${!j}"
                  ;;
                --site-dir=*)
                  site_dir="''${!i#--site-dir=}"
                  ;;
              esac
            done
            if [[ -d "$site_dir" ]]; then
              chmod -R u+w "$site_dir" 2>/dev/null || true
            fi
          '';
          mkdocs-wrapped = pkgs.writeShellScriptBin "mkdocs" ''
            ${pkgs.mkdocs}/bin/mkdocs "$@"
            rc=$?
            ${mkdocsFixPerms}
            exit $rc
          '';
          mkdocs-deploy = pkgs.writeShellScriptBin "mkdocs-deploy" ''
            ${pkgs.mkdocs}/bin/mkdocs gh-deploy "$@"
            rc=$?
            ${mkdocsFixPerms}
            rm -rf "$site_dir"
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
            # mkdocs-wrapped must come before pkgs.mkdocs so the wrapper
            # shadows the raw binary on PATH.
            packages = [
              pkgs.graphviz
              mkdocs-wrapped
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
