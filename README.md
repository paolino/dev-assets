# dev-assets

Shared release infrastructure for the executable repos: one source of truth for
the artifact matrix, the Cachix wiring, and the per-repo recipe a new tool
copies. Consumers pin a tagged release (current: **`v0.1.0`** — see
[releases](https://github.com/paolino/dev-assets/releases)).

```nix
inputs.dev-assets.url = "github:paolino/dev-assets/v0.1.0";
```

```yaml
- uses: paolino/dev-assets/setup-nix@v0.1.0
```

## Artifact matrix (the standard)

Every executable ships the full symmetric matrix:

| Platform        | Runner             | Artifacts                                              |
| --------------- | ------------------ | ------------------------------------------------------ |
| linux x86_64    | `ubuntu-latest` or self-hosted `nixos` | AppImage · DEB · RPM (glibc) · musl static tarball |
| linux aarch64   | `ubuntu-24.04-arm` (native, no QEMU)   | AppImage · DEB · RPM (glibc) · musl static tarball |
| darwin aarch64  | `macos-14`         | relocatable tarball + generated Homebrew formula       |

Plus `<exe>-<version>-<system>.SHA256SUMS` per executable/system. Docker images
are repo-specific and orthogonal to this matrix.

**Hard gate:** no job may compile GHC from source. `setup-nix` declares
`cache.iog.io` + `paolino.cachix.org` as read substituters; the
`aarch64-linux evaluates (GHC cached)` CI job fails closed if the arm GHC would
be built. A repo whose GHC derivation isn't pre-cached self-warms paolino on its
first arm build (one-time), after which it's served from cache.

## Composite actions

- **`setup-nix`** — installs Nix, configures the IOHK + paolino read caches
  (paolino declared as an explicit substituter so fork PRs read it without
  cold-compiling), and optionally pushes newly-built paths to paolino.
  Inputs: `cachix-auth-token` (omit on forks for read-only), `push` (default
  `true`; degrades to read-only when the token is absent).
- **`linux-release`** — builds + smokes the Linux artifacts for one executable
  on the current runner arch and, in `release` mode on a `v*` tag, uploads them
  to the GitHub release. `mode: dev-linux` (PR/dispatch) builds + smokes without
  publishing.
- **`darwin-homebrew-release`** — builds the Darwin tarball + Homebrew formula
  and, on a tag, uploads to the release and updates the tap.

## Nix library (`inputs.dev-assets.lib`)

Deterministic artifact builders project flakes call; networked side effects stay
in the workflows. See [`nix/lib/README.md`](./nix/lib/README.md) for signatures.

- `mkLinuxArtifacts` — AppImage + DEB + RPM (from `glibcPackage`) + optional
  musl tarball (from `muslPackage`), per executable.
- `mkLinuxBundle` / `mkMuslTarball` — the glibc-bundle and musl-tarball halves.
- `mkLinuxArtifactSmoke` — runs each built artifact and greps a usage string
  (configurable `--usage-grep` over combined stdout+stderr).
- `mkDarwinHomebrewBundle` — Darwin tarball + Homebrew formula.

## Graph rendering

Render a small graph directly from this flake, without creating a Nix shell:

```sh
printf '[ A ] -> [ B ]\n' | nix run github:paolino/dev-assets#graph-easy
```

`graph-easy` turns concise node-and-edge descriptions into readable text graphs.

## Wiring recipe (new executable repo)

1. **Flake inputs** — add `bundlers` and pin `dev-assets` to the tag:

   ```nix
   bundlers.url = "github:NixOS/bundlers";
   bundlers.inputs.nixpkgs.follows = "nixpkgs";
   dev-assets.url = "github:paolino/dev-assets/v0.1.0";
   ```

2. **Systems** — include `x86_64-linux`, `aarch64-linux`, `aarch64-darwin`.
   GHC must be `ghc9123` (one GHC keeps warmup + aarch64 + releases coherent).

3. **musl cross** — factor `mkProject = extraModules: cabalProject' { ... }`;
   use `muslProject.projectCross.{musl64,aarch64-multiplatform-musl}` for the
   musl exe. If a static-musl link fails on missing libs, scope the fix in a
   dedicated `muslProject = mkProject [ fixModule ]` using `pkgs.pkgsStatic.<lib>`
   (+ grouped `-optl-Wl,--start-group … --end-group`). NEVER gate that module on
   `pkgs.stdenv.hostPlatform.*` (infinite recursion) and NEVER put a
   `--start-group` link mod in the shared modules list (breaks darwin ld64).

4. **Linux artifacts** — per executable:

   ```nix
   <exe>-linux-release-artifacts = inputs.dev-assets.lib.mkLinuxArtifacts {
     inherit pkgs system;
     executableName = "<exe>";
     version = packageVersion;
     glibcPackage = <exe-glibc>;
     muslPackage  = <exe-musl>;   # or null to skip the musl tarball
     bundlers = inputs.bundlers;
   };
   linux-artifact-smoke = inputs.dev-assets.lib.mkLinuxArtifactSmoke { inherit pkgs system; };
   ```

5. **Darwin/Homebrew** — `mkDarwinHomebrewBundle { inherit pkgs; } { … }` for
   `packages.aarch64-darwin.<exe>-release-artifacts` (see lib README).

6. **`release.yml`** — `arch` matrix `{ x86_64 → ubuntu-latest|nixos, aarch64 →
   ubuntu-24.04-arm }`; `linux-release` in `dev-linux` on `pull_request`,
   `release` on `v*`. `darwin-release.yml` mirrors it with
   `darwin-homebrew-release`. Pin every action `@v0.1.0`.

7. **CI gate** — copy the `aarch64-linux evaluates (GHC cached)` dry-run job
   onto `ubuntu-24.04-arm`.

## Live examples

- [`lambdasistemi/cardano-tx-tools`](https://github.com/lambdasistemi/cardano-tx-tools) — 7 exes, full matrix + Homebrew + docker (released v0.2.3.0).
- [`lambdasistemi/cardano-ledger-rdf`](https://github.com/lambdasistemi/cardano-ledger-rdf) — 3 exes, no rocksdb (clean musl).
- [`cardano-foundation/moog`](https://github.com/cardano-foundation/moog) — 3 exes on GitHub-hosted runners (no self-hosted nixos access).

## Other directories

`mkdocs/`, `asciinema/`, `static-preview/` are independent dev-shell / docs
helpers, not part of the release standard.
