#!/usr/bin/env bash
set -euo pipefail

REGISTRY="${REGISTRY:-ghcr.io}"
REGISTRY_USER="${REGISTRY_USER:-}"
REGISTRY_PASSWORD="${REGISTRY_PASSWORD:-}"
TEMP_DOCKER_CONFIG=""

cleanup() {
    if [ -n "${TEMP_DOCKER_CONFIG}" ]; then
        rm -rf "${TEMP_DOCKER_CONFIG}"
    fi
}
trap cleanup EXIT

if ! command -v docker >/dev/null 2>&1; then
    echo "docker is required to build the devcontainer." >&2
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "docker is installed, but the Docker daemon is not reachable." >&2
    exit 1
fi

if [ -n "${REGISTRY_USER}" ] && [ -n "${REGISTRY_PASSWORD}" ]; then
    TEMP_DOCKER_CONFIG="$(mktemp -d)"
    export DOCKER_CONFIG="${TEMP_DOCKER_CONFIG}"

    echo "${REGISTRY_PASSWORD}" \
        | docker login "${REGISTRY}" -u "${REGISTRY_USER}" --password-stdin
else
    echo "No registry credentials provided; using existing Docker login for ${REGISTRY}."
fi

npx -y @devcontainers/cli build --workspace-folder "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
