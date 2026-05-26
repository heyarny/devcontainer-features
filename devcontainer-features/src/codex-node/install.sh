#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/usr/local/share/codex-devcontainer"
FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

codex_version="${CODEXVERSION-${VERSION:-latest}}"
linked_folders="${LINKEDFOLDERS-${LINKED_FOLDERS-}}"
nvm_version="${NVM_VERSION:-v0.40.4}"
node_version="${NODEVERSION-${NODE_VERSION:-24}}"
npm_version="${NPMVERSION-${NPM_VERSION:-11.15.0}}"

if [ -z "${codex_version}" ]; then
    codex_version="latest"
fi

if [ -z "${node_version}" ]; then
    node_version="24"
fi

if [ -z "${npm_version}" ]; then
    npm_version="11.15.0"
fi

if [[ ! "${codex_version}" =~ ^[0-9A-Za-z._~+-]+$ ]]; then
    echo "Unsupported Codex version '${codex_version}'. Use a semver version or npm dist-tag." >&2
    exit 1
fi

if [[ ! "${node_version}" =~ ^[0-9A-Za-z._~+/*-]+$ ]]; then
    echo "Unsupported Node.js version '${node_version}'. Use a semver version or nvm alias." >&2
    exit 1
fi

if [[ "${npm_version}" != "bundled" ]] && [[ "${npm_version}" != "none" ]] && [[ ! "${npm_version}" =~ ^[0-9A-Za-z._~+-]+$ ]]; then
    echo "Unsupported npm version '${npm_version}'. Use 'bundled', 'none', a semver version, or an npm dist-tag." >&2
    exit 1
fi

export NVM_DIR="${NVM_DIR:-/usr/local/share/nvm}"
export NVM_SYMLINK_CURRENT="${NVM_SYMLINK_CURRENT:-true}"

install_node_with_nvm() {
    if ! command -v apt-get >/dev/null 2>&1; then
        echo "npm is required to install @openai/codex, and automatic Node installation currently requires apt-get." >&2
        exit 1
    fi

    apt-get update
    apt-get install -y --no-install-recommends ca-certificates curl xz-utils

    mkdir -p "${NVM_DIR}"

    if [ ! -s "${NVM_DIR}/nvm.sh" ]; then
        curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${nvm_version}/install.sh" \
            | PROFILE=/dev/null bash
    fi

    # shellcheck disable=SC1091
    . "${NVM_DIR}/nvm.sh"
    nvm install "${node_version}"
    nvm alias default "${node_version}" >/dev/null
    nvm use default >/dev/null
}

link_nvm_binary() {
    local binary="$1"
    local source="${NVM_DIR}/current/bin/${binary}"

    if [ -e "${source}" ]; then
        ln -sf "${source}" "/usr/local/bin/${binary}"
    fi
}

link_nvm_binaries() {
    if [ -d "${NVM_DIR}/current/bin" ]; then
        link_nvm_binary node
        link_nvm_binary npm
        link_nvm_binary npx
        link_nvm_binary corepack
        link_nvm_binary codex
    fi
}

prepare_remote_codex_home() {
    local remote_user="${_REMOTE_USER:-${REMOTE_USER:-${USERNAME:-}}}"
    local remote_home="${_REMOTE_USER_HOME:-}"
    local remote_group

    if [ -n "${remote_user}" ] && ! getent passwd "${remote_user}" >/dev/null 2>&1; then
        remote_user=""
    fi

    if [ -z "${remote_user}" ] && [ -n "${remote_home}" ]; then
        remote_user="$(getent passwd | awk -F: -v home="${remote_home}" '$6 == home { print $1; exit }')"
    fi

    if [ -z "${remote_user}" ]; then
        return
    fi

    if [ -z "${remote_home}" ]; then
        remote_home="$(getent passwd "${remote_user}" | cut -d: -f6)"
    fi

    if [ -z "${remote_home}" ] || [ ! -d "${remote_home}" ]; then
        return
    fi

    remote_group="$(id -gn "${remote_user}")"

    mkdir -p "${remote_home}/.codex"
    chown "${remote_user}:${remote_group}" "${remote_home}/.codex"
    chmod u+rwx "${remote_home}/.codex"
}

if [ -x "${NVM_DIR}/current/bin/npm" ]; then
    export PATH="${NVM_DIR}/current/bin:${PATH}"
fi

if ! command -v npm >/dev/null 2>&1 && [ -s "${NVM_DIR}/nvm.sh" ]; then
    # Some devcontainer builds execute feature scripts in a non-login shell.
    # shellcheck disable=SC1091
    . "${NVM_DIR}/nvm.sh"
    nvm use default >/dev/null
fi

install_node_with_nvm

link_nvm_binaries

npm_prefix="$(npm prefix -g)"
codex_spec="@openai/codex@${codex_version}"

if [ "${npm_version}" != "bundled" ] && [ "${npm_version}" != "none" ]; then
    npm install -g "npm@${npm_version}"
    link_nvm_binaries
    hash -r
fi

if [ -w "${npm_prefix}" ]; then
    npm install -g "${codex_spec}"
else
    sudo env "PATH=${PATH}" "NVM_DIR=${NVM_DIR}" npm install -g "${codex_spec}"
fi

link_nvm_binaries

mkdir -p "${INSTALL_DIR}"

{
    printf 'CODEX_LINKED_FOLDERS_FROM_OPTIONS=%q\n' "${linked_folders}"
} > "${INSTALL_DIR}/options.env"

install -m 0755 "${FEATURE_DIR}/setup-links.sh" "${INSTALL_DIR}/setup-links.sh"

prepare_remote_codex_home

hash -r
codex --version
