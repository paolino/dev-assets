# Linux release composite action

Build Linux flake artifacts (AppImage / DEB / RPM), smoke-test them
against the executable's no-args stderr, optionally publish a
GitHub release, and re-smoke the published assets.

Mirrors `darwin-homebrew-release/` for the Linux side. The two
actions together cover both halves of a Cabal-owned release
pipeline driven by Nix flake outputs.

## Consumer contract

The consumer's flake must expose:

- A package output per release variant. The default naming the
  action expects is `<exe>-linux-release-artifacts` and
  `<exe>-linux-dev-release-artifacts`; pass them via
  `release-output` / `dev-output`.
- A smoke app named `linux-artifact-smoke` (override via
  `smoke-app`) that accepts `--artifacts-dir`,
  `--artifact-version`, `--executable-name`, and `--usage-grep`.
- A version-emitting command (typically
  `scripts/release/get-cabal-version`) supplied via
  `release-version-command`. The action concatenates the git
  short-SHA to it for `dev-linux` mode.

## Worked example

```yaml
jobs:
  linux-bundles:
    name: Build Linux ${{ matrix.executable.name }} bundles
    runs-on: nixos
    strategy:
      fail-fast: false
      matrix:
        executable:
          - name: tx-diff
            release-output: tx-diff-linux-release-artifacts
            dev-output: tx-diff-linux-dev-release-artifacts
            usage-grep: "[--blueprint FILE ...]"
            dev-tag: dev-linux-tx-diff
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0
      - uses: cachix/cachix-action@v17
        with:
          name: paolino
          authToken: ${{ secrets.CACHIX_AUTH_TOKEN }}
      - uses: paolino/dev-assets/linux-release@main
        with:
          mode: >-
            ${{
              github.event_name == 'pull_request' && 'dev-linux'
              || inputs.mode
              || 'release'
            }}
          tag: ${{ github.ref_type == 'tag' && github.ref_name || inputs.tag }}
          publish: ${{ github.event_name == 'push' && 'yes' || inputs.publish || 'no' }}
          release-output: ${{ matrix.executable.release-output }}
          dev-output: ${{ matrix.executable.dev-output }}
          executable-name: ${{ matrix.executable.name }}
          usage-grep: ${{ matrix.executable.usage-grep }}
          dev-tag: ${{ matrix.executable.dev-tag }}
          release-version-command: scripts/release/get-cabal-version
          release-check-command: 'scripts/release/check-version-consistency "$TAG"'
          release-notes-command: 'scripts/release/extract-notes "$TAG"'
          release-title: cardano-tx-tools ${{ github.ref_name }}
          github-token: ${{ github.token }}
```

## Inputs

See `action.yaml` for the canonical list. Required: `mode`,
`release-output`, `dev-output`, `executable-name`, `usage-grep`,
`dev-tag`, `release-version-command`.

## Steps

1. Validate mode, build the chosen flake output, copy artifacts
   to the workspace, and run the `linux-artifact-smoke` app.
2. Upload artifacts as a workflow artifact (toggleable via
   `upload-artifact`).
3. On `release` mode with `publish=yes`: create / reuse the
   GitHub release for `tag` and upload artifacts.
4. On `dev-linux` mode with `workflow_dispatch`: force-update
   `dev-tag` to HEAD, create / refresh the prerelease, upload
   artifacts.
5. On `dev-linux` mode with `workflow_dispatch`: download the
   just-uploaded assets and re-smoke (catches release-asset
   corruption).

## Tests

Run the dispatch integration test locally with:

```
bash linux-release/tests/build-dispatch.sh
```

It PATH-shims `nix` to exercise `build.sh` across release,
dev-linux, and input-validation paths without touching the
real Nix store. CI runs the same script on every PR.
