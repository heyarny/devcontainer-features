#!/usr/bin/env bash
set -euo pipefail

# Optional credentials let CI authenticate without changing the developer's
# existing Docker configuration.
REGISTRY="${REGISTRY:-ghcr.io}"
REGISTRY_USER="${REGISTRY_USER:-}"
REGISTRY_PASSWORD="${REGISTRY_PASSWORD:-}"
TEMP_DOCKER_CONFIG=""

cleanup() {
    # The temporary config can contain registry credentials, so remove it on
    # every exit path.
    if [ -n "${TEMP_DOCKER_CONFIG}" ]; then
        rm -rf "${TEMP_DOCKER_CONFIG}"
    fi
}
trap cleanup EXIT

# Fail with actionable messages before invoking the Dev Container CLI.
if ! command -v docker >/dev/null 2>&1; then
    echo "docker is required to build the devcontainer." >&2
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "docker is installed, but the Docker daemon is not reachable." >&2
    exit 1
fi

if [ -n "${REGISTRY_USER}" ] && [ -n "${REGISTRY_PASSWORD}" ]; then
    # Isolate CI login state instead of overwriting ~/.docker/config.json.
    TEMP_DOCKER_CONFIG="$(mktemp -d)"
    export DOCKER_CONFIG="${TEMP_DOCKER_CONFIG}"

    echo "${REGISTRY_PASSWORD}" \
        | docker login "${REGISTRY}" -u "${REGISTRY_USER}" --password-stdin
else
    # Local runs may reuse credentials already managed by Docker Desktop or the CLI.
    echo "No registry credentials provided; using existing Docker login for ${REGISTRY}."
fi

# Build the repository's devcontainer from its own root regardless of the
# caller's current working directory.
npx -y @devcontainers/cli build --workspace-folder "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
