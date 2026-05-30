# Tasks — Shared Linux nix lib + musl + aarch64 (#27)

## Slice 1 — mk-linux-bundle
- [ ] T27-S1 flake: add `nixpkgs` + `bundlers` inputs + per-system scaffold.
- [ ] T27-S1 GREEN: `nix/lib/mk-linux-bundle.nix` (AppImage/DEB/RPM, configurable
      `artifacts`); export from `nix/lib/default.nix`.
- [ ] T27-S1 proof: self-test builds hello AppImage + DEB + RPM; files exist.

## Slice 2 — mk-musl-tarball
- [ ] T27-S2 GREEN: `nix/lib/mk-musl-tarball.nix` → static `.tar.gz`.
- [ ] T27-S2 proof: `pkgsStatic.hello` tarball extracts; `file` shows statically
      linked; binary runs.

## Slice 3 — smoke + compose
- [ ] T27-S3 GREEN: `nix/lib/mk-linux-artifact-smoke.nix` (musl smoke + artifact
      set) and `nix/lib/mk-linux-artifacts.nix` (compose + SHA256SUMS).
- [ ] T27-S3 proof: full hello matrix builds; smoke passes from extracted form.

## Slice 4 — action arch/musl
- [ ] T27-S4 RED: extend `linux-release/tests/build-dispatch.sh` for `arch` +
      musl staging.
- [ ] T27-S4 GREEN: `linux-release/action.yaml` + `build.sh` handle `arch`
      (x86_64|aarch64) and the musl artifact.

## Slice 5 — self-test CI
- [ ] T27-S5 GREEN: dev-assets flake self-test outputs (hello matrix per system).
- [ ] T27-S5 CI: job builds the x86_64 matrix + aarch64 leg on ubuntu-24.04-arm,
      smokes every artifact from its extracted form.
