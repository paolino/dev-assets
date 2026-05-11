# Darwin Homebrew Release Action

Reusable composite action for macOS release jobs whose installable artifacts are
built by a Nix flake package.

The split is intentional:

- Nix owns deterministic artifact construction: executable bundle, dependent
  dylibs, tarball, SHA256SUMS, generated Homebrew formula, and release metadata.
- The GitHub action owns runner-side orchestration: build invocation, smoke
  tests, workflow artifact upload, GitHub release uploads, tap commits, and
  Homebrew install verification.

Do not move networked release side effects into the Nix derivation. GitHub
release uploads, tap pushes, and Homebrew install tests need credentials,
network access, and a real macOS runner; they belong in CI.

## Caller Contract

The caller must do the platform and repository setup before invoking this
action:

- Run on a macOS runner, normally `macos-14` for `aarch64-darwin`.
- Check out the target repository with enough history for tags and release
  scripts, usually `actions/checkout` with `fetch-depth: 0`.
- Install Nix and configure any substituters/Cachix caches needed by the flake.
- Expose flake packages that build Darwin artifact directories. By default:
  - `.#darwin-release-artifacts`
  - `.#darwin-dev-homebrew-artifacts`
- Provide a Homebrew tap repository and tap name, for example
  `lambdasistemi/homebrew-tap` and `lambdasistemi/tap`.
- Pass `github-token` when publishing GitHub releases.
- Pass `tap-token` only when the selected mode may update the tap.

The action assumes it is invoked from the repository root. Package-specific
version checks, changelog extraction, and smoke tests remain caller-provided
scripts or inline shell snippets.

## Artifact Contract

Each selected flake package must produce one directory containing:

- one Darwin tarball matching `tarball-pattern`
- the selected Homebrew formula file
- `SHA256SUMS`

The shared Nix helper `lib.mkDarwinHomebrewBundle` already emits that layout.
See [the Nix library docs](../nix/lib/README.md) for its full flake API,
parameters, output contract, and limitations:

```text
result/
|-- SHA256SUMS
|-- <formula>.rb
|-- <package>-<version>-aarch64-darwin.tar.gz
`-- release-metadata.json
```

The tarball must unpack into a bundle with executable commands under `bin/`.
The action verifies every command listed in `installed-commands` exists and is
executable before running any caller-provided smoke script.

## Mode Matrix

| Event / mode | Builds artifacts | Tarball smoke | Local tap formula test | Upload workflow artifact | GitHub release upload | Tap update | Tap install test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `pull_request` + `dev-homebrew` | yes | yes | yes, with `file://` tarball URL | yes | no | no | no |
| `workflow_dispatch` + `dev-homebrew` | yes | yes | no | yes | yes, to `dev-tag` | yes when `update-tap: yes` | yes when tap is updated |
| tag push / dispatch + `release` + `publish: no` | yes | yes | no | yes | no | no | no |
| tag push / dispatch + `release` + `publish: yes` | yes | yes | no | yes | yes, to `tag` | yes | yes |

The action does not infer release policy by itself. The workflow should set
`mode`, `publish`, `tag`, and `update-tap` from the event and dispatch inputs.

## Minimal Workflow Shape

```yaml
name: Darwin Release

on:
  push:
    tags: [ "v*" ]
  pull_request:
    branches: [ main ]
    paths:
      - ".github/workflows/darwin-release.yml"
      - "flake.nix"
      - "flake.lock"
      - "nix/**"
  workflow_dispatch:
    inputs:
      mode:
        type: choice
        options: [ "release", "dev-homebrew" ]
        default: "release"
      tag:
        type: string
        required: false
      publish:
        type: choice
        options: [ "no", "yes" ]
        default: "no"
      update_tap:
        type: choice
        options: [ "yes", "no" ]
        default: "yes"

permissions:
  contents: write

jobs:
  build-and-release:
    runs-on: macos-14
    env:
      TAG: ${{ github.ref_type == 'tag' && github.ref_name || inputs.tag }}
      MODE: >-
        ${{
          github.event_name == 'pull_request' && 'dev-homebrew'
          || inputs.mode
          || 'release'
        }}
      PUBLISH: >-
        ${{
          github.event_name == 'push'
          || (inputs.mode != 'dev-homebrew' && inputs.publish == 'yes')
        }}
      UPDATE_TAP: ${{ inputs.update_tap || 'yes' }}
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0
          ref: ${{ github.ref_type == 'tag' && github.ref_name || inputs.tag || github.ref }}

      - uses: cachix/install-nix-action@v30

      - uses: cachix/cachix-action@v17
        with:
          name: paolino
          authToken: ${{ secrets.CACHIX_AUTH_TOKEN }}

      - uses: paolino/dev-assets/darwin-homebrew-release@main
        with:
          mode: ${{ env.MODE }}
          tag: ${{ env.TAG }}
          publish: ${{ env.PUBLISH }}
          update-tap: ${{ env.UPDATE_TAP }}
          release-formula: my-tool.rb
          dev-formula: my-tool-dev.rb
          installed-commands: my-tool helper-tool
          cleanup-formulae: my-tool my-tool-dev
          tap-name: my-org/tap
          tap-repository: my-org/homebrew-tap
          github-token: ${{ github.token }}
          tap-token: ${{ secrets.TAP_TOKEN }}
```

## Amaru-Style Example

This example shows a package that keeps release validation and smoke behavior in
the caller:

```yaml
- name: Build, smoke-test, and optionally publish Darwin Homebrew artifacts
  uses: paolino/dev-assets/darwin-homebrew-release@main
  with:
    mode: ${{ env.MODE }}
    tag: ${{ env.TAG }}
    publish: ${{ env.PUBLISH }}
    update-tap: ${{ env.UPDATE_TAP }}
    dev-tag: dev-homebrew
    release-package: darwin-release-artifacts
    dev-package: darwin-dev-homebrew-artifacts
    release-formula: amaru-treasury-tx.rb
    dev-formula: amaru-treasury-tx-dev.rb
    release-artifact-name: darwin-release-bundle
    dev-artifact-name: darwin-dev-homebrew-artifacts
    tarball-pattern: amaru-treasury-tx-*-aarch64-darwin.tar.gz
    installed-commands: amaru-treasury-tx swap-probe capture-swap-context
    cleanup-formulae: amaru-treasury-tx amaru-treasury-tx-dev
    tap-name: lambdasistemi/tap
    tap-repository: lambdasistemi/homebrew-tap
    github-token: ${{ github.token }}
    tap-token: ${{ secrets.TAP_TOKEN }}
    release-check-command: 'scripts/release/check-version-consistency "$TAG"'
    release-notes-command: 'scripts/release/extract-notes "$TAG"'
    release-title: amaru-treasury-tx ${{ env.TAG }}
    dev-release-title: amaru-treasury-tx dev Homebrew
    tarball-smoke-script: |
      amaru-treasury-tx --help
      capture-swap-context --help
      help_text="$(amaru-treasury-tx swap-wizard --help)"
      printf '%s\n' "$help_text"
      grep -F -- '--extra-signer,--signer SCOPE|HEX' <<<"$help_text" >/dev/null
    brew-smoke-script: |
      amaru-treasury-tx --help
      test -x "$(command -v swap-probe)"
      capture-swap-context --help
      otool -L "$(which amaru-treasury-tx)"
```

## Inputs

| Input | Default | Required | Description |
| --- | --- | --- | --- |
| `mode` | none | yes | `release` or `dev-homebrew`. |
| `tag` | empty | no | Release tag used in `release` mode. Required when publishing or validating a release. |
| `publish` | `no` | no | `yes`/`true` enables release upload and tap update in `release` mode. |
| `update-tap` | `yes` | no | Enables tap update and tap install test for `workflow_dispatch` dev builds. |
| `dev-tag` | `dev-homebrew` | no | Moving tag used for development Homebrew release assets. |
| `release-package` | `darwin-release-artifacts` | no | Flake package output for release artifacts. |
| `dev-package` | `darwin-dev-homebrew-artifacts` | no | Flake package output for dev Homebrew artifacts. |
| `release-formula` | none | yes | Formula filename expected in release artifact output. |
| `dev-formula` | none | yes | Formula filename expected in dev artifact output. |
| `release-artifact-name` | `darwin-release-bundle` | no | Workflow artifact name in release mode. |
| `dev-artifact-name` | `darwin-dev-homebrew-artifacts` | no | Workflow artifact name in dev mode. |
| `tarball-pattern` | `*-aarch64-darwin.tar.gz` | no | `find` pattern used to locate the tarball in the artifact output. |
| `installed-commands` | none | yes | Space-separated commands expected under the tarball's `bin/`. |
| `cleanup-formulae` | empty | no | Formulae to uninstall before Homebrew smoke tests. Include stable and dev formulae when they conflict. |
| `tarball-smoke-script` | empty | no | Shell run after extracting the tarball. `PATH` includes the extracted `bin/`; `DARWIN_BUNDLE_DIR` points to the bundle root. |
| `brew-smoke-script` | empty | no | Shell run after `brew install` and `brew test`. |
| `tap-name` | none | yes | Homebrew tap name passed to `brew tap`, for example `lambdasistemi/tap`. |
| `tap-repository` | none | yes | GitHub repository backing the tap, for example `lambdasistemi/homebrew-tap`. |
| `tap-token` | empty | no | Token used for tap pushes. Required only for paths that update the tap. |
| `github-token` | empty | no | Token used by `gh release`. Required only for paths that publish release assets. |
| `release-check-command` | empty | no | Release validation command. Runs in `release` mode before building with `TAG` exported. |
| `release-notes-command` | empty | no | Command that writes release notes to stdout with `TAG` exported. Used when creating/editing release assets. |
| `release-title` | `<repo> <tag>` | no | GitHub release title in release mode. |
| `dev-release-title` | `<repo> dev Homebrew` | no | GitHub release title in dev mode. |
| `upload-artifact` | `true` | no | Upload generated tarball and formula as a workflow artifact. |
| `retention-days` | `30` | no | Workflow artifact retention period. |

## Outputs

| Output | Description |
| --- | --- |
| `artifact-path` | Built artifact directory. |
| `tarball` | Built Darwin tarball path. |
| `formula` | Generated formula path. |
| `asset` | Tarball basename. |
| `artifact-name` | Workflow artifact name used by upload-artifact. |

## Security and Side Effects

Pull request runs are intentionally limited to local verification:

- The generated formula is copied into a local checkout of the tap.
- The formula URL is rewritten to `file://<built-tarball>`.
- `brew install` and `brew test` run against that local tap formula.
- No release assets are uploaded.
- No tap commits are pushed.

Publishing paths require explicit event/mode inputs and credentials:

- `release` with `publish: yes` uploads to the release tag, updates the stable
  formula in the tap, and installs from the tap.
- `dev-homebrew` on `workflow_dispatch` uploads to `dev-tag`; it updates and
  smoke-tests the dev formula only when `update-tap: yes`.

## Migration Guidance

When moving an existing repository to this action:

1. First expose Darwin artifact packages from the repository flake.
2. Keep the existing workflow and prove the flake outputs with the old shell.
3. Add this action on a spike branch and compare behavior before merging.
4. Check that pull-request mode actually runs the local tap install test.
5. Merge the shared action first.
6. Update consumers from the spike ref to `@main` or to a pinned commit SHA.

For release infrastructure, prefer a pinned SHA when stability and auditability
matter more than automatically receiving shared-action fixes.

## Spike Evidence

This action was spiked against `lambdasistemi/amaru-treasury-tx` before merge:

- Consumer PR: <https://github.com/lambdasistemi/amaru-treasury-tx/pull/54>
- Darwin proof run:
  <https://github.com/lambdasistemi/amaru-treasury-tx/actions/runs/25444009006/job/74642929761>

That run proved:

- the consumer workflow can fetch the action by repository ref
- the action builds `darwin-dev-homebrew-artifacts`
- tarball smoke checks run against the extracted bundle
- local tap install uses the generated dev formula with a `file://` tarball URL
- `brew test` and package-specific smoke checks run after install
- workflow artifact upload still contains the tarball and formula

Keep this section only while the action is still under spike review; remove it
once the action is stable and covered by normal release documentation.
