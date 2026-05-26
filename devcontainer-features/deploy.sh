#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Override REGISTRY and NAMESPACE when publishing somewhere else.
REGISTRY="${REGISTRY:-ghcr.io}"
NAMESPACE="${NAMESPACE:-heyarny/devcontainer-features}"
SOURCE_DIR="${SCRIPT_DIR}/src"

if [ ! -d "${SOURCE_DIR}" ]; then
    echo "Feature source directory does not exist: ${SOURCE_DIR}" >&2
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "docker is required to publish Dev Container Features." >&2
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "docker is installed, but the Docker daemon is not reachable." >&2
    exit 1
fi

if command -v devcontainer >/dev/null 2>&1; then
    DEVCONTAINER_CMD=(devcontainer)
else
    if ! command -v npx >/dev/null 2>&1; then
        echo "devcontainer CLI was not found, and npx is unavailable to run it." >&2
        exit 1
    fi

    DEVCONTAINER_CMD=(npx -y @devcontainers/cli)
fi

REGISTRY_USER="${REGISTRY_USER:-}"
REGISTRY_PASSWORD="${REGISTRY_PASSWORD:-}"
TEMP_DOCKER_CONFIG=""

cleanup() {
    if [ -n "${TEMP_DOCKER_CONFIG}" ]; then
        rm -rf "${TEMP_DOCKER_CONFIG}"
    fi
}
trap cleanup EXIT

if [ -n "${REGISTRY_USER}" ] && [ -n "${REGISTRY_PASSWORD}" ]; then
    TEMP_DOCKER_CONFIG="$(mktemp -d)"
    export DOCKER_CONFIG="${TEMP_DOCKER_CONFIG}"

    echo "${REGISTRY_PASSWORD}" \
        | docker login "${REGISTRY}" -u "${REGISTRY_USER}" --password-stdin
else
    echo "No registry credentials provided; using existing Docker login for ${REGISTRY}."
fi

echo "Publishing Dev Container Features from ${SOURCE_DIR}"
echo "Registry:  ${REGISTRY}"
echo "Namespace: ${NAMESPACE}"

"${DEVCONTAINER_CMD[@]}" features publish "${SOURCE_DIR}" \
    --registry "${REGISTRY}" \
    --namespace "${NAMESPACE}"

echo "Published Dev Container Features:"
while IFS= read -r feature_dir; do
    feature_id="$(basename "${feature_dir}")"
    echo "  ${REGISTRY}/${NAMESPACE}/${feature_id}:1"
done < <(find "${SOURCE_DIR}" -mindepth 1 -maxdepth 1 -type d | sort)
