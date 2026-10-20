# Linux install test composite action

Install the artifacts of `lib.mkLinuxArtifacts` the way a user does, on
machines that have no Nix, and run every command:

- the DEB with `apt-get install` on Ubuntu (`ubuntu:24.04` by default);
- the RPM with `rpm -i` on Fedora (`fedora:41` by default);
- each AppImage as a file on Ubuntu, in a privileged container, because an
  AppImage mounts itself (FUSE) and maps its store (user namespaces), as a
  desktop allows and a default container does not.

Each container is checked to have no `/nix` before the install, and each
command is run from the path the package put it on (`/usr/bin/<command>`), with
`smoke-args` and the output required to contain `usage-grep`.

The extraction smoke (`lib.mkLinuxArtifactSmoke`) runs a program on the build
machine, which already holds its store paths; it cannot see a package that
does not install. This action can: it found a DEB whose archive carried the
store's hard links between store paths, which `dpkg` refuses.

## Use

The runner needs Docker (GitHub's hosted Ubuntu runners have it):

```yaml
- uses: paolino/dev-assets/linux-install-test@<commit>
  with:
    artifacts-dir: artifacts                  # holds <exe>-<version>-<system>.deb etc.
    artifact-version: 1.2.3
    executable-name: my-tool
    commands: my-tool,my-helper               # default: executable-name
    smoke-args: --version                     # default: none
    usage-grep: "my-tool 1.2.3"
```

`artifacts` takes a subset of `appimage,deb,rpm`; `system-suffix`,
`ubuntu-image` and `fedora-image` override the defaults.
