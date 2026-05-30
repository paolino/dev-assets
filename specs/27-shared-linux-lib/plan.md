# Plan — Shared Linux nix lib + musl + aarch64

## Tech stack

Nix flake library under `nix/lib/` + `NixOS/bundlers` (AppImage/DEB/RPM) +
`pkgsStatic` (musl) + bash smoke (writeShellApplication). The dev-assets flake
gains `nixpkgs` + `bundlers` inputs and per-system self-test outputs. GHC-free
sample exes (`hello`, `pkgsStatic.hello`) so the lib is provable in dev-assets
CI without haskell.nix.

## Lib API (committed)

- `mkLinuxBundle  { pkgs, system, executableName, version, artifactVersion ? version, package, bundlers, artifacts ? [ "appimage" "deb" "rpm" ] }`
- `mkMuslTarball  { pkgs, system, executableName, version, artifactVersion ? version, package }`
- `mkLinuxArtifacts { pkgs, system, executableName, version, glibcPackage, muslPackage, bundlers, glibcArtifacts ? <arch default> }` → staged dir + `SHA256SUMS`
- `mkLinuxArtifactSmoke { pkgs, system, artifacts ? [ "appimage" "deb" "rpm" "musl" ] }`

Arch default: `aarch64-linux` → `[ "appimage" ]` glibc + musl; else all three + musl.

## Slices (bisect-safe)

1. **mk-linux-bundle** — generalize the consumer `linux-release.nix` into
   `nix/lib/mk-linux-bundle.nix` with a configurable `artifacts` list; export
   from `nix/lib/default.nix`. Proof: flake self-test builds hello AppImage +
   DEB + RPM; files exist.
2. **mk-musl-tarball** — `nix/lib/mk-musl-tarball.nix`; static `.tar.gz`.
   Proof: build `pkgsStatic.hello` tarball; extract; `file` shows "statically
   linked"; binary runs.
3. **smoke + compose** — `mk-linux-artifact-smoke.nix` (adds musl smoke +
   artifact-set param) and `mk-linux-artifacts.nix` (compose + SHA256SUMS).
   Proof: build full hello matrix; run smoke from extracted form.
4. **action arch/musl** — `linux-release/action.yaml` + `build.sh` gain `arch`
   handling and musl staging. Proof: extend `linux-release/tests/build-dispatch.sh`.
5. **self-test CI** — dev-assets flake self-test outputs + a CI job building the
   x86_64 matrix (and an aarch64 leg on `ubuntu-24.04-arm`), smoking from the
   extracted form.

## Verification

- Local: `./gate.sh` (shellcheck + actionlint + bash tests + `nix build` the
  x86_64 self-test matrix + smoke).
- CI: existing checks + the new self-test job.
