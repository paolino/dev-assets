# Nix Library

`paolino/dev-assets` exposes shared Nix helpers through its flake `lib` output:

```nix
inputs.dev-assets.url = "github:paolino/dev-assets/v0.1.0";
```

Current exports:

- `lib.mkLinuxArtifacts` — AppImage + DEB + RPM (glibc) + optional musl tarball, per executable
- `lib.mkLinuxBundle` — the glibc AppImage/DEB/RPM half
- `lib.mkMuslTarball` — the static musl tarball half
- `lib.mkLinuxArtifactSmoke` — runs each built artifact and greps a usage string
- `lib.mkDarwinHomebrewBundle` — Darwin tarball + generated Homebrew formula

The library is intentionally small. It provides deterministic artifact builders
that project flakes can call, while CI workflows or GitHub Actions handle
networked release side effects. The top-level
[`README.md`](../../README.md) documents the full artifact matrix and the
per-repo wiring recipe.

## Linux helpers

`mkLinuxArtifacts` is the composite entry point — apply it per executable:

```nix
<exe>-linux-release-artifacts = inputs.dev-assets.lib.mkLinuxArtifacts {
  inherit pkgs system;
  executableName = "<exe>";
  version = packageVersion;
  glibcPackage = <exe-glibc>;   # produces AppImage + DEB + RPM
  muslPackage  = <exe-musl>;    # produces the static musl tarball; pass null to skip
  bundlers = inputs.bundlers;   # github:NixOS/bundlers, nixpkgs following yours
};
```

It composes `mkLinuxBundle` (glibc AppImage/DEB/RPM via the NixOS bundlers) and
`mkMuslTarball` (the static tarball). The default artifact set is symmetric:
`[ "appimage" "deb" "rpm" "musl" ]`. Output names follow
`<exe>-<version>-<system>.<ext>` plus a per-exe/system `SHA256SUMS`.

`mkLinuxArtifactSmoke { inherit pkgs system; }` builds a check that runs each
artifact and greps a usage string; override `--usage-grep` when the executable
does not print the default `Usage:` token (e.g. an optparse-applicative tool
that prints `Missing:` on no args, or needs `--help`).

## mkDarwinHomebrewBundle

`mkDarwinHomebrewBundle` packages macOS command-line executables into a
deterministic Darwin tarball and generates the matching Homebrew formula.

It is designed for release workflows that need:

- a relocatable tarball containing `bin/` executables
- bundled non-system dynamic libraries under `libexec/lib/`
- Mach-O load paths rewritten to the bundled dylibs
- a generated Homebrew formula with the correct tarball SHA256
- `SHA256SUMS` and machine-readable release metadata

The helper must be applied to a Darwin `pkgs` set. A Linux machine can still
evaluate metadata for `packages.aarch64-darwin`, but the derivation can only
build on Darwin because it uses Apple Mach-O tooling.

## Usage Pattern

Import the helper by first applying repository-local `pkgs`, then passing
package-specific metadata:

```nix
let
  mkDarwinHomebrewBundle =
    inputs.dev-assets.lib.mkDarwinHomebrewBundle { inherit pkgs; };
in
{
  packages.aarch64-darwin.my-release-artifacts =
    mkDarwinHomebrewBundle {
      pname = "my-tool";
      version = "1.2.3";
      owner = "example";
      desc = "Example command-line tools";
      formulaClass = "MyTool";
      executables = {
        "my-tool" = myTool;
        "helper-tool" = helperTool;
      };
      executableNames = [ "my-tool" "helper-tool" ];
      formulaTest = ''
        assert_predicate bin/"helper-tool", :executable?
        system "#{bin}/my-tool", "--help"
      '';
      smokeCommands = [
        "my-tool --help >/dev/null"
        "helper-tool --help >/dev/null"
      ];
    };
}
```

The values in `executables` must be derivations that expose each command at
`${drv}/bin/<name>`. The names in `executableNames` define both the copied
commands and the Homebrew `bin.install` list.

## Output Layout

The derivation output directory contains:

```text
result/
|-- SHA256SUMS
|-- <formulaName>.rb
|-- <artifactName>
`-- release-metadata.json
```

By default, `<artifactName>` is:

```text
<pname>-<artifactVersion>-<system>.tar.gz
```

For `aarch64-darwin`, that usually means:

```text
my-tool-1.2.3-aarch64-darwin.tar.gz
```

The tarball unpacks to:

```text
./
|-- bin/
|   |-- my-tool
|   `-- helper-tool
`-- libexec/
    `-- lib/
        `-- <copied non-system dylibs>
```

`release-metadata.json` contains:

```json
{
  "pname": "my-tool",
  "version": "1.2.3",
  "artifactVersion": "1.2.3",
  "system": "aarch64-darwin",
  "artifact": "my-tool-1.2.3-aarch64-darwin.tar.gz",
  "formula": "my-tool.rb",
  "releaseTag": "v1.2.3",
  "url": "https://github.com/example/my-tool/releases/download/v1.2.3/my-tool-1.2.3-aarch64-darwin.tar.gz",
  "sha256": "<hex sha256>"
}
```

## Parameters

| Parameter | Default | Required | Description |
| --- | --- | --- | --- |
| `pname` | none | yes | Package name used in default artifact names and default repository name. |
| `version` | none | yes | Upstream package version. |
| `executables` | none | yes | Attribute set mapping command names to derivations. Each command must exist at `${drv}/bin/<name>`. |
| `owner` | none | yes | GitHub owner used in the generated release URL. |
| `repo` | `pname` | no | GitHub repository used in the generated release URL. |
| `executableNames` | `builtins.attrNames executables` | no | Ordered list of commands to copy and install. |
| `artifactVersion` | `version` | no | Version string embedded in the tarball name and derivation name. Useful for dev builds with commit suffixes. |
| `releaseTag` | `v${version}` | no | GitHub release tag used in the formula URL. |
| `artifactName` | `<pname>-<artifactVersion>-<system>.tar.gz` | no | Tarball filename. Override only when a repository has an existing release naming contract. |
| `desc` | none | yes | Homebrew formula description. |
| `homepage` | `https://github.com/${owner}/${repo}` | no | Homebrew formula homepage. |
| `formulaName` | `pname` | no | Homebrew formula filename without `.rb`. |
| `formulaClass` | none | yes | Ruby class name for the generated formula. |
| `formulaVersion` | `artifactVersion` | no | Homebrew formula `version`. |
| `formulaExtraLines` | empty | no | Extra Ruby lines inserted after the `version` line, for example `conflicts_with`. |
| `formulaTest` | executable assertions | no | Ruby body inserted inside `test do`. |
| `smokeCommands` | first executable `--help` | no | Shell commands run against the bundled `bin/` before the tarball is created. |

## Release and Development Outputs

Most repositories should expose two packages: one for immutable releases and one
for a moving development Homebrew build.

```nix
let
  sourceRevision = self.shortRev or (self.dirtyShortRev or "dirty");
  devArtifactVersion = "${packageVersion}-${sourceRevision}";

  mkDarwinHomebrewBundle =
    inputs.dev-assets.lib.mkDarwinHomebrewBundle { inherit pkgs; };

  mkToolBundle = args:
    mkDarwinHomebrewBundle ({
      pname = "my-tool";
      version = packageVersion;
      owner = "example";
      desc = "Example command-line tools";
      formulaClass = "MyTool";
      executables = {
        "my-tool" = myTool;
        "helper-tool" = helperTool;
      };
      executableNames = [ "my-tool" "helper-tool" ];
      smokeCommands = [ "my-tool --help >/dev/null" ];
    } // args);
in
{
  packages.aarch64-darwin.darwin-release-artifacts =
    mkToolBundle { };

  packages.aarch64-darwin.darwin-dev-homebrew-artifacts =
    mkToolBundle {
      artifactVersion = devArtifactVersion;
      releaseTag = "dev-homebrew";
      formulaName = "my-tool-dev";
      formulaClass = "MyToolDev";
      formulaVersion = devArtifactVersion;
      formulaExtraLines =
        "\n  conflicts_with \"my-tool\", because: \"both install the same command-line tools\"";
    };
}
```

This keeps project-specific metadata in the project flake while the bundling
mechanics remain shared.

## How the Bundle Is Built

The derivation performs these steps:

1. Copy each selected executable into `bundle/bin`.
2. Use `otool -L` to find dynamic library dependencies.
3. Ignore system libraries under `/usr/lib`, `/System`, and existing `@...`
   install names.
4. Copy non-system dylibs into `bundle/libexec/lib`.
5. Rewrite executable load paths to `@executable_path/../libexec/lib/<dylib>`.
6. Rewrite bundled dylib IDs to `@loader_path/<dylib>`.
7. Recursively inspect copied dylibs until the non-system dependency queue is
   empty.
8. Run `smokeCommands` with the bundle `bin/` on `PATH`.
9. Create a deterministic tarball with stable ordering, owner, group, and mtime.
10. Compute the tarball SHA256.
11. Write `SHA256SUMS`, `release-metadata.json`, and the Homebrew formula.

## Relationship to the GitHub Action

`mkDarwinHomebrewBundle` builds files. It does not upload them or mutate any
external repository.

Use the `darwin-homebrew-release` composite action for CI-side behavior:

- invoke `nix build`
- smoke-test the tarball on a GitHub macOS runner
- rewrite the generated formula to a local `file://` tarball URL on pull
  requests
- run `brew install` and `brew test`
- upload workflow artifacts
- optionally publish GitHub release assets
- optionally update the Homebrew tap

That boundary keeps Nix builds deterministic and keeps secrets/network access in
GitHub Actions.

## Verification Commands

Useful local checks:

```bash
# Confirm the helper is exported.
nix eval .#lib --apply 'lib: builtins.hasAttr "mkDarwinHomebrewBundle" lib'

# Check a consumer can evaluate Darwin package metadata from Linux.
nix eval .#packages.aarch64-darwin.darwin-release-artifacts.passthru.artifactName
nix eval .#packages.aarch64-darwin.darwin-release-artifacts.passthru.formulaFile

# Build on a Darwin machine.
nix build .#darwin-release-artifacts
nix build .#darwin-dev-homebrew-artifacts
```

The build itself must run on Darwin because it uses `otool` and
`install_name_tool` and asserts `pkgs.stdenv.isDarwin`.

## Limitations

- The helper targets command-line tools, not `.app` bundles or signed/notarized
  macOS applications.
- It does not codesign or notarize binaries.
- It only follows non-system dylibs visible through `otool -L`.
- It expects formulae that install files from the tarball, not formulae that
  build from source.
- It does not publish GitHub releases or update Homebrew taps. Use a workflow or
  composite action for those side effects.

## Amaru Reference

`lambdasistemi/amaru-treasury-tx` is the reference consumer for this helper. It
uses the helper to expose:

- `.#packages.aarch64-darwin.darwin-release-artifacts`
- `.#packages.aarch64-darwin.darwin-dev-homebrew-artifacts`

Those outputs are then consumed by the Darwin release workflow and the shared
Homebrew release action.
