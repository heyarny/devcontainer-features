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
- `codex` supports `version`, `installDir`, `standaloneHome`, `linkFolders`, and
  `configSyncSource`.
- `codex-node` supports `codexVersion`, `nodeVersion`, `npmVersion`, and
  `codexLinkFolders`, and `configSyncSource`.
- Runs folder linking at startup and supervises one foreground config sync
  watcher when `configSyncSource` is configured.

## Example Usage

Install standalone Codex and link workspace-backed state folders:

```jsonc
{
  "features": {
    "ghcr.io/heyarny/devcontainer-features/codex:3.0.0": {
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
    "ghcr.io/heyarny/devcontainer-features/codex-node:2.3.1": {
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

When the container starts, each feature runs folder linking as the remote user.
When `configSyncSource` is configured, the entrypoint starts one foreground
config-sync watcher as that user and waits up to 15 seconds for its initial
reconciliation check before continuing container startup. A missing source is a
valid initial state: startup continues while the watcher waits for the file. If
an invalid or unreadable source prevents initialization for 15 seconds, startup
continues while the supervisor retries. In either case, the source is not
guaranteed to be applied before Codex starts. Once initialized, the same watcher
keeps running so its synchronization baseline is preserved. The entrypoint
restarts it only after it exits, including in clients that do not reliably
re-run devcontainer lifecycle hooks; it does not launch concurrent periodic sync
jobs. Before startup, make the source resolve to a regular file that the remote
user can read and write. If a live config already exists, leave the source empty
or make its content match to avoid an initial conflict.

## Standalone `codex` Options

| Option | Default | Description |
| --- | --- | --- |
| `version` | `latest` | Codex CLI release version to install. Use `latest` to resolve the newest release at build time. The minimum supported release is `0.146.1`. |
| `installDir` | `/usr/local/bin` | Directory where the global `codex` command symlink is installed. |
| `standaloneHome` | `/usr/local/share/codex` | Directory where standalone Codex release payloads are stored. |
| `linkFolders` | empty | Optional folder mappings. Target paths must resolve to absolute container paths. Omit this option when no folder links are needed. |
| `configSyncSource` | empty | Optional absolute container path to a mounted `config.toml` file to sync bidirectionally with `$CODEX_HOME/config.toml`. Startup waits up to 15 seconds for the initial sync check, then continues while synchronization waits or retries as needed. Omit this option to disable config syncing. |

The standalone `codex` feature vendors the official installer served from
`https://chatgpt.com/codex/install.sh`. The installer resolves and verifies
release metadata and assets through `releases.openai.com` by default, with a
verified GitHub Releases fallback. The feature rejects pinned releases older
than `0.146.1` before running the installer.

Containers built with the standalone feature include the same installer as
`/usr/local/share/codex/update.sh`. To update or reinstall Codex inside an
existing container, run:

```bash
sudo /usr/local/share/codex/update.sh
```

Pass `--release VERSION` to install a specific Codex release (`0.146.1` or
newer). The wrapper uses the `installDir` and `standaloneHome` values recorded
when the feature was installed, unless `CODEX_INSTALL_DIR` or `CODEX_HOME` are
set explicitly.

## npm-based `codex-node` Options

| Option | Default | Description |
| --- | --- | --- |
| `codexVersion` | `latest` | Version or npm dist-tag of `@openai/codex` to install. |
| `nodeVersion` | `24` | Node.js version or nvm alias to install. |
| `npmVersion` | `11.15.0` | npm version or dist-tag to install. Use `bundled` or `none` to keep the npm version included with Node.js. |
| `codexLinkFolders` | empty | Optional folder mappings. Target paths must resolve to absolute container paths. Omit this option when no folder links are needed. |
| `configSyncSource` | empty | Optional absolute container path to a mounted `config.toml` file to sync bidirectionally with `$CODEX_HOME/config.toml`. Startup waits up to 15 seconds for the initial sync check, then continues while synchronization waits or retries as needed. Omit this option to disable config syncing. |

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

The repository devcontainer uses the local feature reference for development and
an explicit `workspaceMount` to keep `/workspace` consistent across DevPod and
VS Code.

## Codex Config Mounting

Avoid binding `config.toml` directly to `/home/vscode/.codex/config.toml`.
Recent Codex versions persist config changes by replacing the config file, and
replacing a path that is itself a bind-mounted file can fail. Do not bind the
whole `/home/vscode/.codex` directory either, because Codex also keeps runtime
state there.

Instead, bind the host config file at a separate path and keep
`/home/vscode/.codex/config.toml` as a normal container-local file. Config sync
rejects a symlink at the live config path instead of replacing the link during
an atomic update. Let the feature sync the two files in both directions:

```jsonc
{
  "mounts": [
    "source=${localEnv:HOME}/.codex/config_container.toml,target=/home/vscode/.codex_config.toml,type=bind",
    "source=${localEnv:HOME}/.codex/auth.json,target=/home/vscode/.codex/auth.json,type=bind,readonly",
    "source=${localEnv:HOME}/.codex/skills,target=/home/vscode/.codex/skills,type=bind",
    "source=${localEnv:HOME}/.codex/plugins,target=/home/vscode/.codex/plugins,type=bind"
  ],
  "features": {
    "ghcr.io/heyarny/devcontainer-features/codex:3.0.0": {
      "configSyncSource": "/home/vscode/.codex_config.toml"
    }
  }
}
```

Create `${HOME}/.codex/config_container.toml` on the host before starting the
container. Single-file bind mounts require the source file to exist.

An empty placeholder is safe. Initial reconciliation follows these rules:

- If the configured source is missing, it is never created; the watcher waits
  and leaves the live config unchanged.
- If the source exists but is empty, a nonempty live config seeds it.
- If the source is nonempty and the live config is missing or empty, the source
  seeds the live config.
- If both existing files are empty, neither is copied.
- If both nonempty files are identical, they become the watcher baseline.
- If both files are nonempty and different, both are left untouched instead of
  choosing a winner by timestamp. A message beginning
  `Codex config sync conflict:` is logged.

After that baseline is established, the single watcher propagates one-sided
changes in either direction. Missing or empty content never erases a nonempty
config. After a conflict, the next one-sided nonempty content change selects
that version and resolves the conflict; emptying either side restores the
remaining nonempty version.

## Publish

The default publish target is GHCR:

```text
ghcr.io/heyarny/devcontainer-features/codex:3.0.0
ghcr.io/heyarny/devcontainer-features/codex-node:2.3.1
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
