# Tasks — Package graph-easy (#39)

## Slice A — package, app, and usage documentation

- [X] T39-S1 package: expose nixpkgs' validated `pkgs.graph-easy` as
      `packages.graph-easy` for each supported system.
- [X] T39-S1 app: expose `apps.graph-easy` with `graph-easy` as the executable.
- [X] T39-S1 docs: document a runnable consumer example in `README.md`.
- [X] T39-S1 proof: build the package, run the rendering smoke, and pass
      `nix flake check`.
