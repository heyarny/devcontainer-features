#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/usr/local/share/codex-node"
FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

codex_version="${CODEXVERSION-${VERSION:-latest}}"
codex_link_folders="${CODEXLINKFOLDERS-}"
codex_config_sync_source="${CONFIGSYNCSOURCE:-}"
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

if [ -n "${codex_config_sync_source}" ] && [[ "${codex_config_sync_source}" != /* ]]; then
    echo "configSyncSource must be an absolute container path." >&2
    exit 1
fi

export NVM_DIR="${NVM_DIR:-/usr/local/share/nvm}"
export NVM_SYMLINK_CURRENT="${NVM_SYMLINK_CURRENT:-true}"

install_node_with_nvm() {
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

install_node_with_apk() {
    local installed_node_major requested_node_major

    apk add --no-cache ca-certificates curl xz nodejs npm

    installed_node_major="$(node --version | sed -E 's/^v([0-9]+).*/\1/')"
    requested_node_major="$(printf '%s\n' "${node_version}" | sed -nE 's/^([0-9]+).*/\1/p')"

    if [ -n "${requested_node_major}" ] && [ "${requested_node_major}" != "${installed_node_major}" ]; then
        echo "Alpine package repositories installed Node.js major ${installed_node_major}, but nodeVersion requested ${node_version}." >&2
        echo "Use a matching Node.js major for Alpine images or an apt-based base image for nvm-managed Node.js versions." >&2
        exit 1
    fi
}

install_node() {
    if command -v apt-get >/dev/null 2>&1; then
        install_node_with_nvm
    elif command -v apk >/dev/null 2>&1; then
        install_node_with_apk
    else
        echo "npm is required to install @openai/codex, and automatic Node installation currently supports apt-get or apk." >&2
        exit 1
    fi
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

prepare_codex_home() {
    local remote_user="${_REMOTE_USER:-}"
    local remote_user_home="${_REMOTE_USER_HOME:-}"
    local remote_group

    if [ -z "${remote_user}" ] || [ -z "${remote_user_home}" ] || ! id "${remote_user}" >/dev/null 2>&1; then
        return
    fi

    remote_group="$(id -gn "${remote_user}")"
    mkdir -p "${remote_user_home}/.codex"
    chown "${remote_user}:${remote_group}" "${remote_user_home}/.codex"
}

write_options_env() {
    local options_file="${INSTALL_DIR}/options.env"

    if [ -z "${codex_link_folders}" ] && [ -z "${codex_config_sync_source}" ]; then
        rm -f "${options_file}"
        return
    fi

    {
        if [ -n "${codex_link_folders}" ]; then
            printf 'CODEX_LINK_FOLDERS=%q\n' "${codex_link_folders}"
        fi

        if [ -n "${codex_config_sync_source}" ]; then
            printf 'CODEX_CONFIG_SYNC_SOURCE=%q\n' "${codex_config_sync_source}"
        fi
    } > "${options_file}"
}

if [ -x "${NVM_DIR}/current/bin/npm" ]; then
    export PATH="${NVM_DIR}/current/bin:${PATH}"
fi

if ! command -v npm >/dev/null 2>&1 && [ -s "${NVM_DIR}/nvm.sh" ]; then
    # Some devcontainer builds execute feature scripts in a non-login shell.
    # shellcheck disable=SC1091
    . "${NVM_DIR}/nvm.sh"
    nvm use default >/dev/null 2>&1 || true
fi

install_node

link_nvm_binaries
prepare_codex_home

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
write_options_env

install -m 0755 "${FEATURE_DIR}/link-folders.sh" "${INSTALL_DIR}/link-folders.sh"
install -m 0755 "${FEATURE_DIR}/sync-config.sh" "${INSTALL_DIR}/sync-config.sh"

hash -r
codex --version
