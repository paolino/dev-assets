# dep-graph

Generate a Markdown **dependency graph** for a Nix-flake project: the flake
closure (Nix layer) combined with the package manager's pinned git
dependencies (cabal `source-repository-package` for Haskell), rendered as a
node table, a per-declarer listing, a **pin-skew** report, and a Mermaid
diagram. Every edge carries an exact commit hash, so the graph is verifiable
and reproducible.

Language-dispatched: `haskell` today; the renderer is shared, so adding `rust`
(Cargo git deps) or another extractor is a new `scripts/<lang>.clj` and a case
in `scripts/run.sh` — consumers keep calling the same action.

## Why two layers

- **Flake inputs** (`flake.lock`) — build env, tools, blueprints, genesis.
- **`source-repository-package`** (`cabal.project`) — Haskell library deps,
  pinned by git tag + sha256, **invisible to the Nix closure**. SRPs are not
  transitive, so the root re-pins the union of what its deps declare — and the
  root's pin wins. When a dep declares a *different* rev than the root, that is
  a **pin skew**: the dep is silently built against the root's rev. The graph
  surfaces these explicitly.

## Usage

```yaml
- uses: paolino/dev-assets/setup-nix@v0.0.1   # or run on a nixos runner
  with:
    cachix-auth-token: ${{ secrets.CACHIX_AUTH_TOKEN }}

- uses: paolino/dev-assets/dep-graph@main
  with:
    language: haskell
    owner-regex: "paolino|lambdasistemi|cardano-foundation"
    output: docs/dependencies.md
    title: "my-project dependency graph"
```

### Inputs

| Input | Default | Description |
|-------|---------|-------------|
| `language` | `haskell` | Extractor to use. Supported: `haskell`. |
| `flake-path` | `.` | Root flake / project to analyze. |
| `owner-regex` | — (required) | Regex of managed GitHub orgs to include as nodes. |
| `output` | `docs/dependencies.md` | Output path; `-` for stdout. |
| `title` | `Dependency Graph` | H1 title. |
| `staleness` | `true` | Include "N behind HEAD" / diverged-branch annotations. |

### Output

| Output | Description |
|--------|-------------|
| `path` | Path to the generated Markdown file (empty when `output: '-'`). |

## Deterministic mode (`staleness: false`)

Staleness annotations compare each pinned commit against the **current**
upstream default-branch HEAD — moving external state. A CI drift check that
diffs a committed copy must therefore set `staleness: false`, making the output
a pure function of `flake.lock` + `cabal.project`; it then changes only when
*your* pins change, never because an upstream repo advanced. Use the default
(`staleness: true`) for the human-facing render published to a docs site.

The canonical pattern is **both**: commit a deterministic copy and gate PRs
against it; regenerate the staleness-annotated version live at docs-deploy time.

```yaml
# PR drift gate
- uses: paolino/dev-assets/dep-graph@main
  with: { owner-regex: "...", output: /tmp/fresh.md, staleness: "false" }
- run: diff -u docs/dependencies.md /tmp/fresh.md
        || { echo "::error::dep graph stale — regenerate"; exit 1; }
```

## Requirements

- Nix available (via `setup-nix` or a `nixos` runner); the action pulls
  `babashka`, `gh`, `jq` through `nix shell` when they are not already on PATH.
- `gh` auth via `GH_TOKEN` (the action wires `github.token`). Public dependency
  repos work with the default `GITHUB_TOKEN`; private deps need a token with
  read access to them.

## Implementation

- `scripts/run.sh` — input parsing, tool provisioning, output handling.
- `scripts/haskell.clj` — the flake + cabal extractor and Markdown renderer
  (babashka). Also published as the `haskell-nix-project-graph` skill.
