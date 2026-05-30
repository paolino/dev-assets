# Spec — Harden cachix so no build recompiles GHC

Issue: paolino/dev-assets#26 · Epic: paolino/dev-assets#29

## P1 user story

As a release engineer, I run any dev-assets-based build and observe that GHC
and the cardano crypto closure are substituted from `paolino.cachix.org`
(never compiled from source), on both `ubuntu-latest` and `ubuntu-24.04-arm`.

## Problem

`setup-nix/action.yaml` configures only `cache.iog.io` + `cache.nixos.org` as
read substituters and relies on `cachix-action` to inject `paolino` as a side
effect of authenticating for push. Consequences:

- Fork PRs (no `CACHIX_AUTH_TOKEN`) get **no** `paolino` read substituter at
  all, so they recompile GHC from source.
- There is no guard that fails a job when GHC would be built from source — a
  cache miss is silent and just burns 30-40 min.
- `cachix-warmup` warms GHC only for `aarch64-darwin`; there is no
  `x86_64-linux` / `aarch64-linux` GHC warmup, so the new aarch64-linux build
  matrix (epic #29) would always cold-compile GHC.

## User stories

- US1: As a fork contributor with no cachix token, my CI still reads from
  `paolino` (degrades to read-only push), so I don't recompile GHC.
- US2: As a maintainer, a build that would compile GHC from source fails fast
  with a clear message instead of silently burning runner minutes.
- US3: As an arm64 consumer repo, my `ubuntu-24.04-arm` jobs read GHC from
  `paolino` because warmup populated it.

## Functional requirements

- FR1: `setup-nix` declares `paolino.cachix.org` as a read substituter and its
  public key as a trusted key, in `extra_nix_config` directly (independent of
  the push step).
- FR2: `setup-nix` pushes to `paolino` only when a token is present; absent a
  token (fork PR) it configures read-only and does not fail.
- FR3: A reusable verification step fails the job when a dry-run shows a GHC
  derivation would be built from source.
- FR4: `cachix-warmup` warms `devShells.{x86_64-linux,aarch64-linux}.default.ghc`
  for the epic's in-scope repos.
- FR5: `setup-nix/README.md` documents the read+push model, the push toggle,
  the verification step, and warmup onboarding.
- FR6: `setup-nix` is exercised on an `ubuntu-24.04-arm` runner in dev-assets
  CI.

## Success criteria

- A `setup-nix` invocation without a token configures `paolino` as a
  substituter and skips push without error (asserted by test + actionlint).
- `assert-no-source-ghc.sh` exits non-zero when a dry-run plan contains a
  `ghc` build and zero when it does not (bash test).
- dev-assets CI runs `setup-nix` green on `ubuntu-24.04-arm`.
- `cachix-warmup` has a linux GHC warmup workflow listing the in-scope repos.

## Non-goals

- Artifact format / matrix changes (owned by #27).
- Migrating consumer repos onto `setup-nix` (owned by each consumer child).
- Darwin Homebrew flow changes.
