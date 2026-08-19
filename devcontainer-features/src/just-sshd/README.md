# Just SSHD (Local, Unauthenticated) Dev Container Feature

This experimental Feature allows one existing non-root Dev Container user to
connect over SSH without a client password or key. It depends on the official
Dev Containers `sshd` Feature for package installation, host keys, and server
startup.

> [!WARNING]
> Anyone who can invoke the SSH proxy can log in as the configured user. Use it
> only for local development and do not expose it through a network proxy.

## Options

| Option | Default | Description |
| --- | --- | --- |
| `username` | `automatic` | Existing non-root user allowed to connect. By default, use the Dev Container remote user. |

The Feature deliberately rejects `root`. It empties the selected user's Linux
password and configures OpenSSH to accept its initial `none` authentication
request. Client keys and `authorized_keys` are not involved. OpenSSH server host
keys are still generated and used to encrypt the connection.

## Example

```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:noble",
  "remoteUser": "vscode",
  "features": {
    "ghcr.io/heyarny/devcontainer-features/just-sshd:1": {}
  }
}
```

The Feature configures the container side only. A host-side `ProxyCommand` can
start or find the workspace container and run one SSH server process over
Docker's stdin/stdout transport:

```bash
docker exec -i --user root CONTAINER_ID /usr/sbin/sshd -i
```

This requires no published port. The example repository provides an optional
macOS helper that generates this configuration from the workspace path.

The background listener provided by the upstream `sshd` Feature is restricted
to container loopback as defense in depth. The host connection uses `sshd -i`
over stdin/stdout and does not depend on that listener.
