# Plan — Harden cachix

## Tech stack

GitHub composite action (`setup-nix/action.yaml`) + bash scripts + bash tests
(PATH-shim `nix`, the established `<action>/tests/*.sh` pattern). Gate:
shellcheck + actionlint + the new bash tests + existing linux-release test.

Constant: `paolino.cachix.org` trusted public key
`paolino.cachix.org-1:ecmgO3CXdgSWA2cHlm4srknd/cLFMLmK3i3NrzeDFaE=`.

## Slices (bisect-safe, one commit each)

### Slice A — setup-nix read substituter + push toggle
- `setup-nix/action.yaml`: add `paolino.cachix.org` to `substituters` and its
  key to `trusted-public-keys` in the `install-nix-action` `extra_nix_config`;
  make `cachix-auth-token` optional; pass `skipPush: ${{ token == '' }}` to
  `cachix-action` so a missing token degrades to read-only.
- `setup-nix/tests/config-assertions.sh`: assert action.yaml declares the
  paolino substituter + key and wires `skipPush`. (RED first.)
- Proof: bash test + actionlint (YAML wiring has no unit harness).

### Slice B — "no GHC from source" verification script
- `setup-nix/scripts/assert-no-source-ghc.sh <flake-attr...>`: run
  `nix build --dry-run`, fail if the "will be built" plan contains a
  `*-ghc-*` derivation; print the offending path.
- `setup-nix/tests/assert-no-source-ghc.sh`: shim `nix` to emit dry-run output
  with and without a ghc build; assert exit codes + message. (RED first.)

### Slice C — README + linux warmup + arm CI check
- `setup-nix/README.md`: read+push model, push toggle, verification, warmup
  onboarding recipe.
- `.github/workflows/ci.yml`: add a job running `setup-nix` on
  `ubuntu-24.04-arm` + a trivial `nix store ping` / dry-run, proving FR6.
- `cachix-warmup` linux GHC warmup: companion PR to lambdasistemi/cachix-warmup
  adding `linux-ghc.yml` (x86_64 + aarch64-linux) with the in-scope repos.
  Tracked in this ticket; linked from the PR. (FR4)

## Verification

- Local: `./gate.sh` (shellcheck + bash tests; actionlint if available).
- CI: shellcheck, actionlint, linux-release test, new tests, arm setup-nix job.
