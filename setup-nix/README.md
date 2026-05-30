# setup-nix

Composite action: install Nix, wire the IOHK + `paolino` **read** caches, and
optionally **push** newly built paths to `paolino.cachix.org`.

```yaml
- uses: actions/checkout@v6
- uses: paolino/dev-assets/setup-nix@<tag>
  with:
    cachix-auth-token: ${{ secrets.CACHIX_AUTH_TOKEN }}
```

## Inputs

| Input | Required | Default | Purpose |
|---|---|---|---|
| `cachix-auth-token` | no | `""` | Token for pushing to `paolino`. Omit on fork PRs for read-only. |
| `push` | no | `"true"` | Push newly built paths to `paolino`. Set `"false"` to read-only. |

## Read + push model

The IOHK (`cache.iog.io`), NixOS, and `paolino.cachix.org` caches are declared
as **read substituters** directly in `install-nix-action`'s `extra_nix_config`.
This is deliberate: `paolino` is configured even when no token is present, so
fork PRs and `ubuntu-24.04-arm` runners read GHC from cache instead of
cold-compiling it (~30-40 min).

Push to `paolino` happens via `cachix-action` only when `push` is `true` **and**
a token is present. Otherwise `skipPush` degrades the step to read-only — no
push attempt, no failure.

## Don't recompile GHC: the cachix gate

`haskell.nix` wraps GHC with project-specific patches, so its derivation hash is
unique per repo. If `paolino` hasn't been warmed for that repo, every run
cold-compiles GHC. Guard against silent cache misses in a release job:

```yaml
- run: bash setup-nix/scripts/assert-no-source-ghc.sh '.#default'
```

`assert-no-source-ghc.sh` runs `nix build --dry-run` and fails fast (with the
offending derivation) if GHC appears in the "will be built" section rather than
"will be fetched".

## Warmup onboarding

Pre-warm a repo's GHC into `paolino` so consumers hit cache:

1. Add the repo to `lambdasistemi/cachix-warmup`:
   - `darwin-ghc.yml` → `devShells.aarch64-darwin.default.ghc`
   - `linux-ghc.yml` → `devShells.{x86_64-linux,aarch64-linux}.default.ghc`
2. Trigger the warmup workflow once (manual dispatch).

After that, the repo's release workflow hits cache and skips GHC compilation.
