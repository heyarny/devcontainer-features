#!/usr/bin/env sh
set -eu

# This feature wrapper validates devcontainer options, prepares the image, and
# delegates the actual Codex download to OpenAI's unmodified installer.
FEATURE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
INSTALLER="${FEATURE_DIR}/install-codex-standalone.sh"
VERSION_POLICY="${FEATURE_DIR}/version-policy.sh"
SUPPORT_DIR="/usr/local/share/codex"

# Keep the feature's minimum-version policy outside the vendored installer.
# shellcheck disable=SC1090
. "${VERSION_POLICY}"

# Dev Container Feature options arrive as uppercase environment variables.
codex_version="${VERSION:-latest}"
install_dir="${INSTALLDIR:-/usr/local/bin}"
standalone_home="${STANDALONEHOME:-/usr/local/share/codex}"
codex_link_folders="${LINKFOLDERS:-}"
codex_config_sync_source="${CONFIGSYNCSOURCE:-}"
remote_user="${_REMOTE_USER:-${_CONTAINER_USER:-}}"
remote_user_home="${_REMOTE_USER_HOME:-}"

if [ -z "${codex_version}" ]; then
    codex_version="latest"
fi

# Reject unsupported releases before installing prerequisites or writing files.
codex_feature_validate_release "${codex_version}"

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

    # Entrypoint hooks source this file on every container start. Remove stale
    # optional settings when neither feature option is enabled.
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
    # Produce a source-safe POSIX shell value without interpreting its contents.
    printf '%s' "$1" | sed "s/'/'\\\\''/g; s/^/'/; s/$/'/"
}

write_install_env() {
    install_env_file="${SUPPORT_DIR}/install.env"

    # The update wrapper uses these persisted paths when no explicit override
    # is supplied, so updates land in the original installation locations.
    {
        printf 'CODEX_FEATURE_INSTALL_DIR=%s\n' "$(quote_env_value "${install_dir}")"
        printf 'CODEX_FEATURE_STANDALONE_HOME=%s\n' "$(quote_env_value "${standalone_home}")"
    } > "${install_env_file}"
    chmod 0644 "${install_env_file}"
}

write_runtime_env() {
    runtime_env_file="${SUPPORT_DIR}/runtime.env"

    # Older feature runners may provide only the username; resolve its home so
    # runtime hooks can operate on the intended user's Codex configuration.
    if [ -z "${remote_user_home}" ] && [ -n "${remote_user}" ] && command -v getent >/dev/null 2>&1; then
        remote_user_home="$(getent passwd "${remote_user}" | cut -d: -f6 || true)"
    fi

    {
        if [ -n "${remote_user}" ]; then
            printf 'CODEX_FEATURE_REMOTE_USER=%s\n' "$(quote_env_value "${remote_user}")"
        fi

        if [ -n "${remote_user_home}" ]; then
            printf 'CODEX_FEATURE_REMOTE_USER_HOME=%s\n' "$(quote_env_value "${remote_user_home}")"
        fi
    } > "${runtime_env_file}"
    chmod 0644 "${runtime_env_file}"
}

install_prerequisites() {
    # Support Debian-family and Alpine images explicitly because their package
    # names and privilege-switching tools differ.
    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -y --no-install-recommends bash ca-certificates curl tar gzip gawk
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache bash ca-certificates curl tar gzip gawk runuser
    else
        echo "Automatic Codex installation currently supports apt-get or apk base images." >&2
        exit 1
    fi
}

install_prerequisites

mkdir -p "${install_dir}" "${standalone_home}" "${SUPPORT_DIR}"

# Pass the normalized feature choices through the upstream installer's public
# environment interface; the upstream script itself remains byte-for-byte intact.
CODEX_NON_INTERACTIVE=true \
CODEX_RELEASE="${codex_version}" \
CODEX_INSTALL_DIR="${install_dir}" \
CODEX_HOME="${standalone_home}" \
    sh "${INSTALLER}"

# The installer commonly runs as root; make its verified payload traversable
# and executable by the container's remote user.
chmod -R a+rX "${standalone_home}"
chmod 0755 "${install_dir}/codex"

# Persist build-time choices before installing the runtime and update helpers.
write_options_env
write_install_env
write_runtime_env

install -m 0755 "${FEATURE_DIR}/entrypoint.sh" "${SUPPORT_DIR}/entrypoint.sh"
install -m 0755 "${FEATURE_DIR}/install-codex-standalone.sh" "${SUPPORT_DIR}/install-codex-standalone.sh"
install -m 0755 "${FEATURE_DIR}/update.sh" "${SUPPORT_DIR}/update.sh"
install -m 0755 "${FEATURE_DIR}/version-policy.sh" "${SUPPORT_DIR}/version-policy.sh"
install -m 0755 "${FEATURE_DIR}/link-folders.sh" "${SUPPORT_DIR}/link-folders.sh"
install -m 0755 "${FEATURE_DIR}/sync-config.sh" "${SUPPORT_DIR}/sync-config.sh"

# Refresh the shell's command cache, then fail the build if Codex cannot run.
hash -r 2>/dev/null || true
"${install_dir}/codex" --version
