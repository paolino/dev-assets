# Plan — Package graph-easy

## Tech stack

Nix flake outputs backed by nixpkgs' top-level `pkgs.graph-easy` package. The
candidate was validated against current `nixos-unstable`: version 0.76 builds
and its `graph-easy` executable renders a sample graph. The older suggested
`perlPackages.GraphEasy` attribute is absent.

## Slice A — package, app, and usage documentation

- Add `packages.graph-easy = pkgs.graph-easy` to the existing per-system root
  outputs.
- Add `apps.graph-easy` with `flake-utils.lib.mkApp`, explicitly naming the
  `graph-easy` executable.
- Add a concise README section showing a piped node/edge example through
  `nix run github:paolino/dev-assets#graph-easy`.

This is one bisect-safe slice: the package/app wiring and its user-facing usage
contract land together.

## Verification

- Pre-change RED: `nix build --no-link .#graph-easy` and
  `nix run .#graph-easy -- --help` fail because the output does not exist.
- GREEN: `nix build --no-link .#graph-easy`.
- Smoke: pipe `[ A ] -> [ B ]` to `nix run .#graph-easy` and require a rendered
  box-and-arrow graph containing both node labels.
- Repository gate: `nix flake check`.
