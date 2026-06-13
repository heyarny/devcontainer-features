#!/usr/bin/env sh
set -eu

FEATURE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
INSTALLER="${FEATURE_DIR}/install-codex-standalone.sh"
SUPPORT_DIR="/usr/local/share/codex"

codex_version="${VERSION:-latest}"
install_dir="${INSTALLDIR:-/usr/local/bin}"
standalone_home="${STANDALONEHOME:-/usr/local/share/codex}"
codex_link_folders="${LINKFOLDERS:-}"
codex_config_sync_source="${CONFIGSYNCSOURCE:-}"

if [ -z "${codex_version}" ]; then
    codex_version="latest"
fi

case "${codex_version}" in
    latest|rust-v[0-9A-Za-z._~+-]*|[0-9A-Za-z._~+-]*)
        ;;
    *)
        echo "Unsupported Codex version '${codex_version}'. Use 'latest' or a Codex release version." >&2
        exit 1
        ;;
esac

if [ "${install_dir#/}" = "${install_dir}" ] || [ "${standalone_home#/}" = "${standalone_home}" ]; then
    echo "installDir and standaloneHome must be absolute paths." >&2
    exit 1
fi

if [ -n "${codex_config_sync_source}" ] && [ "${codex_config_sync_source#/}" = "${codex_config_sync_source}" ]; then
    echo "configSyncSource must be an absolute container path." >&2
    exit 1
fi

write_options_env() {
    options_file="${SUPPORT_DIR}/options.env"

    if [ -z "${codex_link_folders}" ] && [ -z "${codex_config_sync_source}" ]; then
        rm -f "${options_file}"
        return
    fi

    {
        if [ -n "${codex_link_folders}" ]; then
            printf 'CODEX_LINK_FOLDERS=%s\n' "$(printf '%s' "${codex_link_folders}" | sed "s/'/'\\\\''/g; s/^/'/; s/$/'/")"
        fi

        if [ -n "${codex_config_sync_source}" ]; then
            printf 'CODEX_CONFIG_SYNC_SOURCE=%s\n' "$(printf '%s' "${codex_config_sync_source}" | sed "s/'/'\\\\''/g; s/^/'/; s/$/'/")"
        fi
    } > "${options_file}"
    chmod 0644 "${options_file}"
}

quote_env_value() {
    printf '%s' "$1" | sed "s/'/'\\\\''/g; s/^/'/; s/$/'/"
}

write_install_env() {
    install_env_file="${SUPPORT_DIR}/install.env"

    {
        printf 'CODEX_FEATURE_INSTALL_DIR=%s\n' "$(quote_env_value "${install_dir}")"
        printf 'CODEX_FEATURE_STANDALONE_HOME=%s\n' "$(quote_env_value "${standalone_home}")"
    } > "${install_env_file}"
    chmod 0644 "${install_env_file}"
}

install_prerequisites() {
    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -y --no-install-recommends bash ca-certificates curl tar gzip gawk
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache bash ca-certificates curl tar gzip gawk
    else
        echo "Automatic Codex installation currently supports apt-get or apk base images." >&2
        exit 1
    fi
}

install_prerequisites

mkdir -p "${install_dir}" "${standalone_home}" "${SUPPORT_DIR}"

CODEX_NON_INTERACTIVE=true \
CODEX_RELEASE="${codex_version}" \
CODEX_INSTALL_DIR="${install_dir}" \
CODEX_HOME="${standalone_home}" \
    sh "${INSTALLER}"

chmod -R a+rX "${standalone_home}"
chmod 0755 "${install_dir}/codex"

write_options_env
write_install_env

install -m 0755 "${FEATURE_DIR}/install-codex-standalone.sh" "${SUPPORT_DIR}/install-codex-standalone.sh"
install -m 0755 "${FEATURE_DIR}/update.sh" "${SUPPORT_DIR}/update.sh"
install -m 0755 "${FEATURE_DIR}/link-folders.sh" "${SUPPORT_DIR}/link-folders.sh"
install -m 0755 "${FEATURE_DIR}/sync-config.sh" "${SUPPORT_DIR}/sync-config.sh"

hash -r 2>/dev/null || true
"${install_dir}/codex" --version
