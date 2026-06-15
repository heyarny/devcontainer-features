# OpenAI Codex with Node.js Dev Container Feature

Installs Node.js, npm, and the OpenAI Codex CLI. It can also link Codex state
folders from `$CODEX_HOME` into the workspace after the workspace mount is
available.

Consumers do not need to add a separate Node/npm feature. This feature installs
Node.js 24 and npm 11.15.0 by default, and can override either version when
needed.

## Options

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

Use the comma-separated string form for `codexLinkFolders`. It is portable across
Dev Container tools; arrays may be serialized differently by different clients.

Each `codexLinkFolders` entry uses `name=target`. The `name` is created under
`$CODEX_HOME`. The `target` must resolve to an absolute container path.

At container start, the feature runs
`/usr/local/share/codex-node/link-folders.sh` and
`/usr/local/share/codex-node/sync-config.sh` as the remote user. It then keeps a
small supervisor loop alive that restarts the config sync watcher if it exits.
The sync script exits immediately unless `configSyncSource` is set. Use this
when you want a host-backed Codex config without mounting over Codex's live
config path:

```jsonc
{
  "mounts": [
    "source=${localEnv:HOME}/.codex/config_container.toml,target=/home/vscode/.codex_config.toml,type=bind"
  ],
  "features": {
    "ghcr.io/heyarny/devcontainer-features/codex-node:2.3.0": {
      "configSyncSource": "/home/vscode/.codex_config.toml"
    }
  }
}
```

Create `${HOME}/.codex/config_container.toml` on the host before starting the
container. Single-file bind mounts require the source file to exist.

## Example

Install Codex only:

```jsonc
{
  "features": {
    "ghcr.io/heyarny/devcontainer-features/codex-node:2.3.0": {}
  }
}
```

Install Codex and link workspace-backed state folders:

```jsonc
{
  "features": {
    "ghcr.io/heyarny/devcontainer-features/codex-node:2.3.0": {
      "codexVersion": "latest",
      "codexLinkFolders": "sessions=${containerWorkspaceFolder}/.codex/sessions,archived_sessions=${containerWorkspaceFolder}/.codex/archived_sessions"
    }
  }
}
```
