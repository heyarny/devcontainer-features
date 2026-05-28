# OpenAI Codex with Node.js Dev Container Feature

Installs Node.js, npm, and the OpenAI Codex CLI. It can also link Codex state
folders from `$CODEX_HOME` into the workspace after the workspace mount is
available.

Consumers do not need to add a separate Node/npm feature. This feature installs
Node.js 24 with nvm and npm 11.15.0 by default, and can
override either version when needed.

## Options

| Option | Default | Description |
| --- | --- | --- |
| `codexVersion` | `latest` | Version or npm dist-tag of `@openai/codex` to install. |
| `nodeVersion` | `24` | Node.js version or nvm alias to install. |
| `npmVersion` | `11.15.0` | npm version or dist-tag to install. Use `bundled` or `none` to keep the npm version included with Node.js. |
| `codexLinkFolders` | empty | Optional folder mappings. Target paths must resolve to absolute container paths. Omit this option when no folder links are needed. |

Use the comma-separated string form for `codexLinkFolders`. It is portable across
Dev Container tools; arrays may be serialized differently by different clients.

Each `codexLinkFolders` entry uses `name=target`. The `name` is created under
`$CODEX_HOME`. The `target` must resolve to an absolute container path.

The feature declares a `postCreateCommand` that runs
`/usr/local/share/codex-node/link-folders.sh` after the workspace mount is
available. If your devcontainer client does not run Feature lifecycle metadata,
add that script as a top-level devcontainer `postCreateCommand`.

## Example

Install Codex only:

```jsonc
{
  "features": {
    "ghcr.io/heyarny/devcontainer-features/codex-node:2.0.0": {}
  }
}
```

Install Codex and link workspace-backed state folders:

```jsonc
{
  "features": {
    "ghcr.io/heyarny/devcontainer-features/codex-node:2.0.0": {
      "codexVersion": "latest",
      "codexLinkFolders": "sessions=${containerWorkspaceFolder}/.codex/sessions,archived_sessions=${containerWorkspaceFolder}/.codex/archived_sessions"
    }
  }
}
```
