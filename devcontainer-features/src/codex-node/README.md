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
| `configSyncSource` | empty | Optional absolute container path to a mounted `config.toml` file to sync bidirectionally with `$CODEX_HOME/config.toml`. Startup waits up to 15 seconds for the initial sync check, then continues while synchronization waits or retries as needed. Omit this option to disable config syncing. |

On apt-based images, `nodeVersion` is installed with nvm and can be a semver
version or nvm alias. On Alpine images, Node.js and npm are installed with
`apk`; the requested `nodeVersion` must match the major version available from
the Alpine package repository.

Use the comma-separated string form for `codexLinkFolders`. It is portable across
Dev Container tools; arrays may be serialized differently by different clients.

Each `codexLinkFolders` entry uses `name=target`. The `name` is created under
`$CODEX_HOME`. The `target` must resolve to an absolute container path.

At container start, the feature runs
`/usr/local/share/codex-node/link-folders.sh` as the remote user. When
`configSyncSource` is set, the entrypoint runs
`/usr/local/share/codex-node/sync-config.sh --watch` as one foreground process
and waits up to 15 seconds for its initial reconciliation check before continuing
startup. If the source is missing, startup continues while that watcher waits
for the file. If an invalid or unreadable source prevents initialization for 15
seconds, startup continues while the supervisor retries. In either case, the
source is not guaranteed to be applied before Codex starts. Once initialized,
keeping reconciliation and watching in the same process preserves its
synchronization baseline. The entrypoint restarts the watcher only after it
exits; it does not run concurrent periodic reconciliations. Before startup, make
the source resolve to a regular file that the remote user can read and write. If
a live config already exists, leave the source empty or make its content match
to avoid an initial conflict. Use this when you want a host-backed Codex config
without mounting over Codex's live config path:

Keep `$CODEX_HOME/config.toml` as a regular container-local file. Config sync
rejects a symlink at that live path instead of replacing the link.

```jsonc
{
  "mounts": [
    "source=${localEnv:HOME}/.codex/config_container.toml,target=/home/vscode/.codex_config.toml,type=bind"
  ],
  "features": {
    "ghcr.io/heyarny/devcontainer-features/codex-node:2.3.1": {
      "configSyncSource": "/home/vscode/.codex_config.toml"
    }
  }
}
```

Create `${HOME}/.codex/config_container.toml` on the host before starting the
container. Single-file bind mounts require the source file to exist.

The host placeholder may be empty. A missing configured source is never created;
the watcher waits and leaves the live config unchanged. An existing empty source
is seeded from a nonempty live config, while a nonempty source seeds a missing or
empty live config. Identical nonempty files become the watcher baseline. If both
files are nonempty and different, both are left untouched and a message beginning
`Codex config sync conflict:` is logged. The watcher then propagates one-sided
changes in either direction, but missing or empty content never erases a
nonempty config. After a conflict, the next one-sided nonempty content change
selects that version and resolves the conflict; emptying either side restores
the remaining nonempty version.

## Example

Install Codex only:

```jsonc
{
  "features": {
    "ghcr.io/heyarny/devcontainer-features/codex-node:2.3.1": {}
  }
}
```

Install Codex and link workspace-backed state folders:

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
