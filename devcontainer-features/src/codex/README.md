# OpenAI Codex CLI Dev Container Feature

Installs the standalone OpenAI Codex CLI globally. This feature does not install
Node.js or npm. It can also link Codex state folders from `$CODEX_HOME` into the
workspace after the workspace mount is available.

The feature vendors the official Codex standalone installer and runs it with
image-wide paths so `codex` is available to all container users:

```text
/usr/local/bin/codex
/usr/local/share/codex/packages/standalone
```

## Options

| Option | Default | Description |
| --- | --- | --- |
| `version` | `latest` | Codex CLI release version to install. Use `latest` to resolve the newest release at build time. |
| `installDir` | `/usr/local/bin` | Directory where the global `codex` command symlink is installed. |
| `standaloneHome` | `/usr/local/share/codex` | Directory where standalone Codex release payloads are stored. |
| `linkFolders` | empty | Optional folder link mappings. Target paths must resolve to absolute container paths. Omit this option when no folder links are needed. |

The vendored installer downloads release assets from GitHub. It does not fetch
the installer script from `chatgpt.com` during the devcontainer build.

For large build matrices or environments that hit GitHub API rate limits, pass a
`GITHUB_TOKEN` during the build. The vendored installer uses it only for
`api.github.com` requests. The token is optional for normal installs.

Use the comma-separated string form for `linkFolders`. Each entry uses
`name=target`. The `name` is created under `$CODEX_HOME`; `target` must resolve
to an absolute container path.

The feature declares a `postCreateCommand` that runs
`/usr/local/share/codex/link-folders.sh` after the workspace mount is available.
If your devcontainer client does not run Feature lifecycle metadata, add that
script as a top-level devcontainer `postCreateCommand`.

## Example

```jsonc
{
  "features": {
    "ghcr.io/heyarny/devcontainer-features/codex:1.0.2": {
      "version": "latest",
      "linkFolders": "sessions=${containerWorkspaceFolder}/.codex/sessions,archived_sessions=${containerWorkspaceFolder}/.codex/archived_sessions"
    }
  }
}
```
