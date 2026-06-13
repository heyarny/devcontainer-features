# Codex Dev Container Features

This repository contains example devcontainer setup for running Codex in a
container, plus Dev Container Features for installing Codex.

The `codex` feature installs the standalone OpenAI Codex CLI globally without
Node.js or npm. The `codex-node` feature installs Node.js, npm, and the npm-based
OpenAI Codex CLI. Both support folder linking: selected folders under
`$CODEX_HOME` can be symlinked to project-local folders after the workspace
mount is available. This is useful for keeping Codex state, such as `sessions`
and `archived_sessions`, inside the project host workspace instead of only
inside the container home.

## Feature

- `codex`: installs the standalone Codex CLI globally at `/usr/local/bin/codex`
  and provides `/usr/local/share/codex/update.sh` for manual updates
  inside an existing container.
- `codex-node`: installs Node.js 24, npm 11.15.0, and `@openai/codex`.
- Both features support apt-based and Alpine-based Microsoft Dev Container base
  images.
- `codex` supports `version`, `installDir`, `standaloneHome`, and `linkFolders`.
- `codex-node` supports `codexVersion`, `nodeVersion`, `npmVersion`, and
  `codexLinkFolders`.
- Provides a folder-linking script that can run after the workspace mount is
  available.

## Example Usage

Install standalone Codex and link workspace-backed state folders:

```jsonc
{
  "features": {
    "ghcr.io/heyarny/devcontainer-features/codex:1.1.1": {
      "version": "latest",
      "linkFolders": "sessions=${containerWorkspaceFolder}/.codex/sessions,archived_sessions=${containerWorkspaceFolder}/.codex/archived_sessions"
    }
  }
}
```

Install npm-based Codex with Node.js and workspace-backed state folders:

```jsonc
{
  "features": {
    "ghcr.io/heyarny/devcontainer-features/codex-node:2.2.0": {
      "codexVersion": "latest",
      "codexLinkFolders": "sessions=${containerWorkspaceFolder}/.codex/sessions,archived_sessions=${containerWorkspaceFolder}/.codex/archived_sessions"
    }
  }
}
```

That creates links like:

```text
/home/vscode/.codex/sessions -> /workspace/.codex/sessions
/home/vscode/.codex/archived_sessions -> /workspace/.codex/archived_sessions
```

Folder-link options are intentionally documented as strings. Arrays of strings
are not portable across tools; DevPod serializes them differently than the Dev
Containers CLI. Use the comma-separated string form for predictable behavior.

Each feature declares a `postCreateCommand` that links folders after the
workspace mount is available. It also declares a `postStartCommand` that starts
the config sync watcher on every container start. If your devcontainer client
does not run Feature lifecycle metadata, add the relevant scripts as top-level
devcontainer lifecycle commands:

```jsonc
{
  "postCreateCommand": "/usr/local/share/codex/link-folders.sh",
  "postStartCommand": "/usr/local/share/codex/sync-config.sh"
}
```

Use `/usr/local/share/codex/link-folders.sh` and
`/usr/local/share/codex/sync-config.sh` for `codex`, or
`/usr/local/share/codex-node/link-folders.sh` and
`/usr/local/share/codex-node/sync-config.sh` for `codex-node`.

## Standalone `codex` Options

| Option | Default | Description |
| --- | --- | --- |
| `version` | `latest` | Codex CLI release version to install. Use `latest` to resolve the newest release at build time. |
| `installDir` | `/usr/local/bin` | Directory where the global `codex` command symlink is installed. |
| `standaloneHome` | `/usr/local/share/codex` | Directory where standalone Codex release payloads are stored. |
| `linkFolders` | empty | Optional folder mappings. Target paths must resolve to absolute container paths. Omit this option when no folder links are needed. |
| `configSyncSource` | empty | Optional absolute container path to a mounted `config.toml` file to sync bidirectionally with `$CODEX_HOME/config.toml`. Omit this option to disable config syncing. |

The standalone `codex` feature vendors the official Codex installer and uses
GitHub release APIs to resolve and verify downloads. For large build matrices or
rate-limited environments, pass `GITHUB_TOKEN` during the build; it is used only
for `api.github.com` requests and is optional for normal installs.

Containers built with the standalone feature include the same installer as
`/usr/local/share/codex/update.sh`. To update or reinstall Codex inside an
existing container, run:

```bash
sudo /usr/local/share/codex/update.sh
```

Pass `--release VERSION` to install a specific Codex release. The wrapper uses
the `installDir` and `standaloneHome` values recorded when the feature was
installed, unless `CODEX_INSTALL_DIR` or `CODEX_HOME` are set explicitly.

## npm-based `codex-node` Options

| Option | Default | Description |
| --- | --- | --- |
| `codexVersion` | `latest` | Version or npm dist-tag of `@openai/codex` to install. |
| `nodeVersion` | `24` | Node.js version or nvm alias to install. |
| `npmVersion` | `11.15.0` | npm version or dist-tag to install. Use `bundled` or `none` to keep the npm version included with Node.js. |
| `codexLinkFolders` | empty | Optional folder mappings. Target paths must resolve to absolute container paths. Omit this option when no folder links are needed. |
| `configSyncSource` | empty | Optional absolute container path to a mounted `config.toml` file to sync bidirectionally with `$CODEX_HOME/config.toml`. Omit this option to disable config syncing. |

On apt-based images, `nodeVersion` is installed with nvm and can be a semver
version or nvm alias. On Alpine images, Node.js and npm are installed with
`apk`; the requested `nodeVersion` must match the major version available from
the Alpine package repository.

Each folder-link entry uses `name=target`. The `name` is created under
`$CODEX_HOME`; `target` must resolve to an absolute container path.

## Local DevPod Check

From the repository root:

```bash
devpod delete devcontainer-features
devpod up . --ide none
ssh devcontainer-features.devpod 'node --version; npm --version; codex --version; readlink /home/vscode/.codex/sessions'
```

The repository devcontainer uses the published Feature reference and an explicit
`workspaceMount` to keep `/workspace` consistent across DevPod and VS Code. Its
top-level `postCreateCommand` and `postStartCommand` are retained for DevPod
compatibility.

## Codex Config Mounting

Avoid binding `config.toml` directly to `/home/vscode/.codex/config.toml`.
Recent Codex versions persist config changes by replacing the config file, and
replacing a path that is itself a bind-mounted file can fail. Do not bind the
whole `/home/vscode/.codex` directory either, because Codex also keeps runtime
state there.

Instead, bind the host config file at a separate path, keep
`/home/vscode/.codex/config.toml` as a normal container-local file, and sync the
two files in both directions after the container is created or started:

```jsonc
{
  "mounts": [
    "source=${localEnv:HOME}/.codex/config_container.toml,target=/home/vscode/.codex_config.toml,type=bind",
    "source=${localEnv:HOME}/.codex/auth.json,target=/home/vscode/.codex/auth.json,type=bind,readonly",
    "source=${localEnv:HOME}/.codex/skills,target=/home/vscode/.codex/skills,type=bind",
    "source=${localEnv:HOME}/.codex/plugins,target=/home/vscode/.codex/plugins,type=bind"
  ],
  "features": {
    "ghcr.io/heyarny/devcontainer-features/codex:1.1.1": {
      "configSyncSource": "/home/vscode/.codex_config.toml"
    }
  }
}
```

Create `${HOME}/.codex/config_container.toml` on the host before starting the
container. Single-file bind mounts require the source file to exist.

## Publish

The default publish target is GHCR:

```text
ghcr.io/heyarny/devcontainer-features/codex:1.1.1
ghcr.io/heyarny/devcontainer-features/codex-node:2.2.0
```

Login to GHCR, then publish with the Dev Container CLI:

```bash
echo "<github-token-with-write:packages>" \
  | docker login ghcr.io -u "<github-user>" --password-stdin

devcontainer features publish devcontainer-features/src \
  --registry ghcr.io \
  --namespace heyarny/devcontainer-features
```

Feature versions are defined in each
`devcontainer-features/src/<feature>/devcontainer-feature.json`. Bump them
before publishing a new release; already-published versions are skipped by the
Dev Container CLI.

## Test

From the repository root:

```bash
devcontainer features test --features codex --base-image mcr.microsoft.com/devcontainers/base:noble devcontainer-features
devcontainer features test --features codex --base-image mcr.microsoft.com/devcontainers/base:bookworm devcontainer-features
devcontainer features test --features codex --base-image mcr.microsoft.com/devcontainers/base:alpine devcontainer-features

devcontainer features test --features codex-node --base-image mcr.microsoft.com/devcontainers/base:noble devcontainer-features
devcontainer features test --features codex-node --base-image mcr.microsoft.com/devcontainers/base:bookworm devcontainer-features
devcontainer features test --features codex-node --base-image mcr.microsoft.com/devcontainers/base:trixie devcontainer-features
devcontainer features test --features codex-node --base-image mcr.microsoft.com/devcontainers/base:alpine devcontainer-features
```

## Resources

- [Dev Containers](https://containers.dev/)
- [Dev Container Features](https://containers.dev/features)
- [Dev Containers base images](https://hub.docker.com/r/microsoft/devcontainers)
- [DevPod](https://devpod.sh/)
