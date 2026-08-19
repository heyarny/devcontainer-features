# OpenAI Codex CLI Dev Container Feature

Installs the standalone OpenAI Codex CLI globally. This feature does not install
Node.js or npm. It can also link Codex state folders from `$CODEX_HOME` into the
workspace after the workspace mount is available.

The feature vendors the official Codex standalone installer and runs it with
image-wide paths so `codex` is available to all container users:

```text
/usr/local/bin/codex
/usr/local/share/codex/packages/standalone
/usr/local/share/codex/update.sh
```

## Options

| Option | Default | Description |
| --- | --- | --- |
| `version` | `latest` | Codex CLI release version to install. Use `latest` to resolve the newest release at build time. The minimum supported release is `0.146.1`. |
| `installDir` | `/usr/local/bin` | Directory where the global `codex` command symlink is installed. |
| `standaloneHome` | `/usr/local/share/codex` | Directory where standalone Codex release payloads are stored. |
| `linkFolders` | empty | Optional folder link mappings. Target paths must resolve to absolute container paths. Omit this option when no folder links are needed. |
| `configSyncSource` | empty | Optional absolute container path to a mounted `config.toml` file to sync bidirectionally with `$CODEX_HOME/config.toml`. Startup waits up to 15 seconds for the initial sync check, then continues while synchronization waits or retries as needed. Omit this option to disable config syncing. |

The installer is vendored byte-for-byte from
`https://chatgpt.com/codex/install.sh`; it is not fetched dynamically during the
devcontainer build. It downloads verified release metadata and assets from
`releases.openai.com` by default and falls back to verified GitHub Releases
downloads when necessary. The feature rejects pinned releases older than
`0.146.1` before running the installer.

The feature also installs the same standalone installer as a simple update
command at `/usr/local/share/codex/update.sh`. To update or reinstall
Codex inside an existing container, run:

```bash
sudo /usr/local/share/codex/update.sh
```

Pass `--release VERSION` to install a specific Codex release (`0.146.1` or
newer). The wrapper uses the `installDir` and `standaloneHome` values recorded
when the feature was installed, unless `CODEX_INSTALL_DIR` or `CODEX_HOME` are
set explicitly.

Use the comma-separated string form for `linkFolders`. Each entry uses
`name=target`. The `name` is created under `$CODEX_HOME`; `target` must resolve
to an absolute container path.

At container start, the feature runs `/usr/local/share/codex/link-folders.sh`
as the remote user. When `configSyncSource` is set, the entrypoint runs
`/usr/local/share/codex/sync-config.sh --watch` as one foreground process and
waits up to 15 seconds for its initial reconciliation check before continuing
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
    "ghcr.io/heyarny/devcontainer-features/codex:3.0.0": {
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
