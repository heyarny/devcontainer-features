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
| `version` | `latest` | Codex CLI release version to install. Use `latest` to resolve the newest release at build time. |
| `installDir` | `/usr/local/bin` | Directory where the global `codex` command symlink is installed. |
| `standaloneHome` | `/usr/local/share/codex` | Directory where standalone Codex release payloads are stored. |
| `linkFolders` | empty | Optional folder link mappings. Target paths must resolve to absolute container paths. Omit this option when no folder links are needed. |
| `configSyncSource` | empty | Optional absolute container path to a mounted `config.toml` file to sync bidirectionally with `$CODEX_HOME/config.toml`. Omit this option to disable config syncing. |

The vendored installer downloads release assets from GitHub. It does not fetch
the installer script from `chatgpt.com` during the devcontainer build.

For large build matrices or environments that hit GitHub API rate limits, pass a
`GITHUB_TOKEN` during the build. The vendored installer uses it only for
`api.github.com` requests. The token is optional for normal installs.

The feature also installs the same standalone installer as a simple update
command at `/usr/local/share/codex/update.sh`. To update or reinstall
Codex inside an existing container, run:

```bash
sudo /usr/local/share/codex/update.sh
```

Pass `--release VERSION` to install a specific Codex release. The wrapper uses
the `installDir` and `standaloneHome` values recorded when the feature was
installed, unless `CODEX_INSTALL_DIR` or `CODEX_HOME` are set explicitly.

Use the comma-separated string form for `linkFolders`. Each entry uses
`name=target`. The `name` is created under `$CODEX_HOME`; `target` must resolve
to an absolute container path.

At container start, the feature runs `/usr/local/share/codex/link-folders.sh`
and `/usr/local/share/codex/sync-config.sh` as the remote user. It then keeps a
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
    "ghcr.io/heyarny/devcontainer-features/codex:2.0.0": {
      "configSyncSource": "/home/vscode/.codex_config.toml"
    }
  }
}
```

Create `${HOME}/.codex/config_container.toml` on the host before starting the
container. Single-file bind mounts require the source file to exist.

## Example

```jsonc
{
  "features": {
    "ghcr.io/heyarny/devcontainer-features/codex:2.0.0": {
      "version": "latest",
      "linkFolders": "sessions=${containerWorkspaceFolder}/.codex/sessions,archived_sessions=${containerWorkspaceFolder}/.codex/archived_sessions"
    }
  }
}
```
