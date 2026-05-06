# Shared Static Preview Action

Publishes an already-built static directory to the shared preview host:

```text
https://preview.dev.plutimus.com/<owner>/<repo>/pr-<number>/
```

The action has two modes:

- `publish`: copy a static directory into `/opt/services/previews/<owner>/<repo>/pr-<number>/`, emit the preview URL, and optionally upsert a PR comment.
- `cleanup`: remove the preview directory when the PR closes.

## Requirements

- Run on a self-hosted runner that can write to `/opt/services/previews`.
- Use it from `pull_request` workflows, or pass `pr-number` explicitly.
- Give the workflow enough permissions to comment on pull requests when `comment` is `true`.

## Example

```yaml
name: Preview

on:
  pull_request:
    types:
      - opened
      - synchronize
      - reopened
      - ready_for_review
      - closed

permissions:
  contents: read
  issues: write
  pull-requests: write

jobs:
  preview:
    if: github.event.action != 'closed'
    runs-on: nixos
    steps:
      - uses: actions/checkout@v6
      - run: ./build-static-site.sh
      - uses: paolino/dev-assets/static-preview@main
        with:
          path: site-root

  preview-cleanup:
    if: github.event.action == 'closed'
    runs-on: nixos
    steps:
      - uses: paolino/dev-assets/static-preview@main
        with:
          mode: cleanup
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `mode` | `publish` | `publish` or `cleanup`. |
| `path` | `site-root` | Static directory to publish. Ignored in cleanup mode. |
| `preview-root` | `/opt/services/previews` | Filesystem root served by the preview host. |
| `preview-host` | `https://preview.dev.plutimus.com` | Public preview base URL. |
| `owner` | current repository owner | Preview URL owner segment. |
| `repository` | current repository name | Preview URL repository segment. |
| `pr-number` | current pull request number | Pull request number for the preview path. |
| `comment` | `true` | Upsert a PR comment with the preview URL when publishing. |
| `comment-marker` | `<!-- shared-static-preview-url -->` | Marker used to update an existing comment. |

## Outputs

| Output | Description |
| --- | --- |
| `preview-url` | Public preview URL. |
| `preview-path` | Filesystem preview directory. |
