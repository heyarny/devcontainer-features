# Codex Node Dev Container Feature

This repository contains an example devcontainer setup for running Codex in a
container, plus the `codex-node` Dev Container Feature.

The feature installs Node.js, npm, and the OpenAI Codex CLI. Its main
customization is `linkFolders`: selected folders under `$CODEX_HOME` can be
symlinked to project-local folders after the workspace mount is available. This
is useful for keeping Codex state, such as `sessions` and `archived_sessions`,
inside the project host workspace instead of only inside the container home.

## Feature

- `codex-node`: installs Node.js 24, npm 11.15.0, and `@openai/codex`.
- Supports `codexVersion`, `nodeVersion`, and `npmVersion`.
- Supports `linkFolders` mappings from `$CODEX_HOME/<name>` to workspace
  folders.
- Provides a folder-linking script that can run after the workspace mount is
  available.

## Example Usage

```jsonc
{
  "features": {
    "ghcr.io/heyarny/devcontainer-features/codex-node:1.0.3": {
      "codexVersion": "latest",
      "linkFolders": "sessions=.codex/sessions,archived_sessions=.codex/archived_sessions"
    }
  }
}
```

That creates links like:

```text
/home/vscode/.codex/sessions -> /workspace/.codex/sessions
/home/vscode/.codex/archived_sessions -> /workspace/.codex/archived_sessions
```

`linkFolders` is intentionally documented as a string. Arrays of strings are
not portable across tools; DevPod serializes them differently than the Dev
Containers CLI. Use the comma-separated string form for predictable behavior.

The feature declares a `postCreateCommand` that runs
`/usr/local/share/codex-node/link-folders.sh` after the workspace mount is
available. If your devcontainer client does not run Feature lifecycle metadata,
add that script as a top-level devcontainer `postCreateCommand`.

## Options

| Option | Default | Description |
| --- | --- | --- |
| `codexVersion` | `latest` | Version or npm dist-tag of `@openai/codex` to install. |
| `nodeVersion` | `24` | Node.js version or nvm alias to install. |
| `npmVersion` | `11.15.0` | npm version or dist-tag to install. Use `bundled` or `none` to keep the npm version included with Node.js. |
| `linkFolders` | empty | Optional folder mappings. Omit this option when no folder links are needed. |

Each `linkFolders` entry uses `name=target`. The `name` is created under
`$CODEX_HOME`; relative `target` values resolve under the workspace. Targets may
also use `{workspace}`, `{workspaceFolder}`, or `{localWorkspaceFolder}`.

## Local DevPod Check

From the repository root:

```bash
devpod delete devcontainer-features
devpod up . --ide none
ssh devcontainer-features.devpod 'node --version; npm --version; codex --version; readlink /home/vscode/.codex/sessions'
```

The repository devcontainer uses the published image-based Feature reference and
an explicit `workspaceMount` to keep `/workspace` consistent across DevPod and
VS Code. Its top-level `postCreateCommand` is retained for DevPod compatibility.

## Publish

The default publish target is GHCR:

```text
ghcr.io/heyarny/devcontainer-features/codex-node:1.0.3
```

Login to GHCR, then publish with the Dev Container CLI:

```bash
echo "<github-token-with-write:packages>" \
  | docker login ghcr.io -u "<github-user>" --password-stdin

devcontainer features publish devcontainer-features/src \
  --registry ghcr.io \
  --namespace heyarny/devcontainer-features
```

The feature version is defined in
`devcontainer-features/src/codex-node/devcontainer-feature.json`. Bump it before
publishing a new release; already-published versions are skipped by the Dev
Container CLI.

## Test

From the repository root:

```bash
devcontainer features test --features codex-node --base-image mcr.microsoft.com/devcontainers/base:noble devcontainer-features
```

## Resources

- [Dev Containers](https://containers.dev/)
- [Dev Container Features](https://containers.dev/features)
- [Dev Containers base images](https://hub.docker.com/r/microsoft/devcontainers)
- [DevPod](https://devpod.sh/)
