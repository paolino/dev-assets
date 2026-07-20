# Spec — Package graph-easy as a flake output

Issue: paolino/dev-assets#39

## P1 user story

As a consumer of `dev-assets`, I can render node/edge descriptions with
`nix run github:paolino/dev-assets#graph-easy -- ...` without creating an
ad-hoc Nix shell.

## Functional requirements

- FR1: Expose nixpkgs' Graph::Easy package as `packages.graph-easy` on every
  system currently supported by the root flake.
- FR2: Expose `apps.graph-easy` with `graph-easy` as its executable.
- FR3: Document a runnable example in the top-level README alongside the
  repository's other development helpers.

## Success criteria

- `nix build .#graph-easy` succeeds.
- `nix run .#graph-easy` renders a simple two-node graph.
- `nix flake check` succeeds.
- The README example identifies the direct flake invocation consumers use.

## Non-goals

- CI or release-matrix changes.
- Changes to the independent helper/action trees.
- Packaging a different graph renderer.
