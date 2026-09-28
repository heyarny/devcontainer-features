# Agent Sandbox (Bubblewrap) Dev Container Feature

Installs `bubblewrap` on Debian/Ubuntu images with `apt-get` or Alpine images
with `apk`.
Codex uses `bwrap` and seccomp for its Linux command sandbox. This Feature can be
used alongside either Codex Feature; it does not install or configure Codex.

## Example

The registry reference becomes available after this Feature is published.

```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:noble",
  // Use this when Docker blocks bwrap from creating user namespaces.
  "runArgs": ["--security-opt=seccomp=unconfined"],
  "features": {
    "ghcr.io/heyarny/devcontainer-features/codex:3.0.1": {},
    "ghcr.io/heyarny/devcontainer-features/agent-sandbox:1": {}
  }
}
```

Try the container without `runArgs` first. Set it in the consuming
`devcontainer.json` if Docker blocks `bwrap` from creating a user namespace; a
Feature cannot set container runtime options during image build. Docker
recommends keeping its [default seccomp profile](https://docs.docker.com/engine/security/seccomp/).
A tested custom profile can preserve more of Docker's filtering;
`seccomp=unconfined` disables that filter for the whole container. The host must
also allow user namespaces, and an Ubuntu AppArmor policy can still block them.
See [OpenAI's sandbox prerequisites](https://learn.chatgpt.com/docs/sandboxing#prerequisites)
and [container guidance](https://learn.chatgpt.com/docs/agent-approvals-security#os-level-sandbox).

If you rely on the container as a security boundary, avoid exposing the Docker
daemon socket inside it: Docker warns that daemon access can grant control over
host filesystems. Keep credentials out of containers used for untrusted projects.
See [Docker's daemon security guidance](https://docs.docker.com/engine/security/#docker-daemon-attack-surface).
