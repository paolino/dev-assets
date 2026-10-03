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
          # Material renders ```mermaid fences natively but, unless `mermaid` is
          # already defined, fetches it from unpkg at read time — outside any
          # pinned, byte-verified site. Consumers copy this file into their site
          # assets and list it in `extra_javascript` so no page loads a CDN.
          mermaid-js = pkgs.fetchurl {
            url = "https://unpkg.com/mermaid@11.17.2/dist/mermaid.min.js";
            hash = "sha256-WB7X10vZBI0OOpE2OSfXLvIpQtdyJUayf3zCnjU5Drg=";
          };
          # Renders each page with the site's own Markdown engine and writes what
          # the reader sees as PAGE.speech.json (see the header of bin/mkdocs-speech).
          mkdocs-speech =
            let
              python = pkgs.python3.withPackages (ps: [
                ps.markdown
                ps.pymdown-extensions
                ps.pyyaml
              ]);
            in
            pkgs.writeShellScriptBin "mkdocs-speech" ''
              exec ${python}/bin/python3 ${./bin/mkdocs-speech} "$@"
            '';
        in
        {
          packages = plugins // { inherit mkdocs-speech mermaid-js; };
          # The companion of a fixture page must equal what a reader sees, and
          # the same comparison must fail on an altered expectation.
          checks.speech =
            pkgs.runCommand "mkdocs-speech-check" { nativeBuildInputs = [ pkgs.python3 ]; }
              ''
                python3 ${./test/speech}/check.py ${mkdocs-speech}/bin/mkdocs-speech
                python3 ${./test/speech}/check.py ${mkdocs-speech}/bin/mkdocs-speech --control
                touch $out
              '';
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

            # Pinned Mermaid for sites that vendor it (see mermaid-js above).
            MERMAID_JS = "${mermaid-js}";

            shellHook = ''
              echo "MkDocs environment ready!"
              echo "Run: mkdocs serve"
            '';
          };
        };
    };
}
