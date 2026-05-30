# Tasks — Harden cachix (#26)

## Slice A — setup-nix read substituter + push toggle
- [ ] T26-S1 RED: `setup-nix/tests/config-assertions.sh` asserts paolino
      substituter + key + `skipPush` wiring; fails against current action.yaml.
- [ ] T26-S1 GREEN: edit `setup-nix/action.yaml` to add the paolino read
      substituter + trusted key and the `skipPush` toggle on missing token.
- [ ] T26-S1 gate: shellcheck + actionlint + config-assertions test green.

## Slice B — no-GHC-from-source verification
- [ ] T26-S2 RED: `setup-nix/tests/assert-no-source-ghc.sh` shims nix dry-run
      (with/without ghc build) and asserts exit codes + message.
- [ ] T26-S2 GREEN: `setup-nix/scripts/assert-no-source-ghc.sh` implements the
      dry-run scan.
- [ ] T26-S2 gate: shellcheck + the new test green.

## Slice C — README + linux warmup + arm CI
- [ ] T26-S3 README: `setup-nix/README.md` documents read+push, toggle,
      verification, warmup onboarding.
- [ ] T26-S3 CI: `.github/workflows/ci.yml` runs `setup-nix` on
      `ubuntu-24.04-arm` + a trivial nix check.
- [ ] T26-S3 warmup: companion PR to lambdasistemi/cachix-warmup adds
      `linux-ghc.yml` (x86_64 + aarch64-linux) with in-scope repos; linked.
