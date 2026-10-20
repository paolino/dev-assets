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
    nixpkgs.lib.recursiveUpdate
    ({ inherit lib; }
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
        # A product of two commands installed together: one AppImage per
        # command, one DEB and one RPM that put both on the path.
        helloAgain = pkgs.writeShellScriptBin "hello-again" ''
          exec ${pkgs.hello}/bin/hello --greeting="Hello again" "$@"
        '';
        helloPair = pkgs.symlinkJoin {
          name = "hello-pair";
          paths = [ pkgs.hello helloAgain ];
          meta.mainProgram = "hello";
        };
        selfTestMulti = lib.mkLinuxArtifacts {
          inherit pkgs system bundlers;
          executableName = "hello";
          version = "2.12.1";
          commands = [ "hello" "hello-again" ];
          # hello-again's AppImage carries its own package only
          commandPackages = { hello-again = helloAgain; };
          # data beside the commands, at a path its users can name
          packageLinks = { "usr/share/hello-pair" = "${pkgs.hello}/share"; };
          glibcPackage = helloPair;
          glibcArtifacts = glibcArtifacts;
        };
        selfTestMultiSmoke = pkgs.writeShellApplication {
          name = "self-test-multi-smoke";
          runtimeInputs = [ selfTestSmokeHarness pkgs.coreutils pkgs.dpkg pkgs.gnugrep ];
          text = ''
            linux-artifact-smoke \
              --artifacts-dir ${selfTestMulti} \
              --artifact-version 2.12.1 \
              --executable-name hello \
              --commands hello,hello-again \
              --artifacts appimage,deb,rpm \
              --usage-grep "Hello"
            # arguments instead of none
            linux-artifact-smoke \
              --artifacts-dir ${selfTestMulti} \
              --artifact-version 2.12.1 \
              --executable-name hello \
              --commands hello,hello-again \
              --artifacts appimage,deb,rpm \
              --smoke-args "--version" \
              --usage-grep "GNU Hello"
            # one DEB, both commands on the path, and the whole closure inside
            listing="$(dpkg-deb -c ${selfTestMulti}/hello-2.12.1-${system}.deb)"
            grep -q "./usr/bin/hello ->" <<<"$listing"
            grep -q "./usr/bin/hello-again ->" <<<"$listing"
            grep -q "./usr/share/hello-pair ->" <<<"$listing"
            grep -q "glibc" <<<"$listing"
            # a control: a command the package does not carry is refused
            if linux-artifact-smoke --artifacts-dir ${selfTestMulti} --artifact-version 2.12.1 \
              --executable-name hello --commands hello,absent --artifacts appimage >/dev/null 2>&1; then
              echo "self-test-multi-smoke: a missing command passed" >&2
              exit 1
            fi
            echo "self-test-multi-smoke: OK"
          '';
        };
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
        packages.self-test-multi = selfTestMulti;
        packages.self-test-multi-smoke = selfTestMultiSmoke;
        packages.graph-easy = pkgs.graph-easy;
        apps.graph-easy = flake-utils.lib.mkApp {
          drv = pkgs.graph-easy;
          exePath = "/bin/graph-easy";
        };
      }))
    # The macOS Homebrew helper, both ways: the commands it bundles itself, and
    # a tarball the caller assembled (one top directory, its commands in bin/).
    {
      packages.aarch64-darwin =
        let
          pkgs = nixpkgs.legacyPackages.aarch64-darwin;
          mk = lib.mkDarwinHomebrewBundle { inherit pkgs; };
          common = {
            pname = "hello";
            version = "2.12.1";
            owner = "paolino";
            repo = "dev-assets";
            desc = "Self-test of the Homebrew helper";
            formulaClass = "Hello";
            executableNames = [ "hello" ];
            smokeCommands = [ "hello --version" ];
          };
          helloTarball = pkgs.runCommand "hello-prebuilt.tar.gz"
            { nativeBuildInputs = [ pkgs.gnutar pkgs.gzip ]; } ''
            mkdir -p hello-2.12.1/bin
            cp ${pkgs.hello}/bin/hello hello-2.12.1/bin/hello
            tar -czf "$out" hello-2.12.1
          '';
        in
        {
          darwin-self-test = mk (common // { executables = { hello = pkgs.hello; }; });
          darwin-self-test-prebuilt = mk (common // { bundleTarball = helloTarball; });
        };
    };
}
