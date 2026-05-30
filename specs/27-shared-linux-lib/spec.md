# Spec — Shared Linux nix lib + musl + aarch64

Issue: paolino/dev-assets#27 · Epic: paolino/dev-assets#29 · Depends on #26.

## P1 user story

As a consumer repo, I import one `dev-assets` nix builder and the
`linux-release` action and obtain AppImage + DEB + RPM + musl tarball for
`x86_64-linux` and AppImage + musl tarball for `aarch64-linux`, without copying
any plumbing.

## Problem

The Linux release plumbing (`nix/linux-release.nix` + `nix/linux-artifact-smoke.nix`)
is copy-pasted into each consumer (cardano-tx-tools, cardano-ledger-rdf), and
covers only `x86_64-linux` glibc AppImage/DEB/RPM. There is no shared builder,
no musl static tarball, and no aarch64 support. dev-assets already ships
`nix/lib/mk-darwin-homebrew-bundle.nix` for Darwin — Linux has no equivalent.

## Functional requirements

- FR1: `nix/lib/mk-linux-bundle.nix` produces a configurable set of glibc
  artifacts (AppImage, DEB, RPM) for a package + system via `NixOS/bundlers`.
- FR2: `nix/lib/mk-musl-tarball.nix` produces a static musl `.tar.gz` from a
  statically-linked package, for `x86_64` and `aarch64`.
- FR3: `nix/lib/mk-linux-artifacts.nix` composes the glibc bundle + musl tarball
  into one staged directory with a single `SHA256SUMS`, arch-aware (aarch64
  omits DEB/RPM).
- FR4: `nix/lib/mk-linux-artifact-smoke.nix` extracts and smoke-tests every
  artifact (AppImage, DEB, RPM, musl tarball) from its packaged form,
  parameterized by the artifact set.
- FR5: `linux-release/action.yaml` accepts an `arch` input (`x86_64` |
  `aarch64`); aarch64 builds run on `ubuntu-24.04-arm`.
- FR6: dev-assets CI self-tests the full matrix for a GHC-free sample
  executable (`hello` / `pkgsStatic.hello`) and smokes every artifact from its
  extracted form.

## Artifact matrix

| System | AppImage | DEB | RPM | musl tarball |
|---|---|---|---|---|
| x86_64-linux | ✓ | ✓ | ✓ | ✓ |
| aarch64-linux | ✓ | — | — | ✓ |

## Success criteria

- `nix build .#<self-test>` builds the full x86_64 matrix; smoke passes from
  extracted form; the musl tarball binary is statically linked.
- The aarch64 self-test (AppImage + musl) builds on `ubuntu-24.04-arm`.
- A consumer can delete its `nix/linux-release.nix` + `nix/linux-artifact-smoke.nix`
  and call the shared lib (proven in #119 / #70, not here).

## Non-goals

- Migrating consumer repos (owned by #119 / #70 / #135).
- Cachix wiring (owned by #26).
- aarch64 **GHC** cache evidence — that is a consumer concern; the self-test
  here is GHC-free (`hello`), so it does not touch the warmup story.
- Darwin changes.
