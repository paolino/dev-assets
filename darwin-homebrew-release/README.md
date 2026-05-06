# Darwin Homebrew Release Action

Composite action for Darwin release jobs whose artifacts are produced by a
Nix flake package. It keeps the deterministic build in Nix and the networked
release/tap side effects in GitHub Actions.

The caller is responsible for checkout, Nix installation, and cache setup.

```yaml
- uses: paolino/dev-assets/darwin-homebrew-release@main
  with:
    mode: ${{ env.MODE }}
    tag: ${{ env.TAG }}
    publish: ${{ env.PUBLISH }}
    update-tap: ${{ env.UPDATE_TAP }}
    release-formula: amaru-treasury-tx.rb
    dev-formula: amaru-treasury-tx-dev.rb
    installed-commands: amaru-treasury-tx swap-probe capture-swap-context
    cleanup-formulae: amaru-treasury-tx amaru-treasury-tx-dev
    tap-name: lambdasistemi/tap
    tap-repository: lambdasistemi/homebrew-tap
    github-token: ${{ github.token }}
    tap-token: ${{ secrets.TAP_TOKEN }}
    release-check-command: 'scripts/release/check-version-consistency "$TAG"'
    release-notes-command: 'scripts/release/extract-notes "$TAG"'
```

Use `tarball-smoke-script` and `brew-smoke-script` for package-specific smoke
checks.
