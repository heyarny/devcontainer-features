#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/usr/local/share/codex-node"
runtime_env_file="${INSTALL_DIR}/runtime.env"
startup_log="/tmp/codex-startup.log"

if [ -f "${runtime_env_file}" ]; then
    # shellcheck disable=SC1090
    . "${runtime_env_file}"
fi

run_feature_command() {
    local command_path="$1"
    local command_name="$2"
    local log_mode="${3:-normal}"

    if [ "${log_mode}" != "quiet" ]; then
        printf '[%s] starting %s as uid=%s user=%s\n' "$(date -Iseconds)" "${command_name}" "$(id -u)" "$(id -un)" >> "${startup_log}"
    fi

    if [ ! -x "${command_path}" ]; then
        printf '[%s] %s is not executable\n' "$(date -Iseconds)" "${command_path}" >> "${startup_log}"
        return
    fi

    if [ "$(id -u)" = "0" ] && [ -n "${CODEX_FEATURE_REMOTE_USER:-}" ] && [ "${CODEX_FEATURE_REMOTE_USER}" != "root" ] && id "${CODEX_FEATURE_REMOTE_USER}" >/dev/null 2>&1 && command -v runuser >/dev/null 2>&1; then
        remote_home="${CODEX_FEATURE_REMOTE_USER_HOME:-}"
        if [ -z "${remote_home}" ] && command -v getent >/dev/null 2>&1; then
            remote_home="$(getent passwd "${CODEX_FEATURE_REMOTE_USER}" | cut -d: -f6 || true)"
        fi

        if [ "${log_mode}" != "quiet" ]; then
            printf '[%s] running %s as %s with HOME=%s\n' "$(date -Iseconds)" "${command_name}" "${CODEX_FEATURE_REMOTE_USER}" "${remote_home:-/home/${CODEX_FEATURE_REMOTE_USER}}" >> "${startup_log}"
        fi
        runuser -u "${CODEX_FEATURE_REMOTE_USER}" -- env HOME="${remote_home:-/home/${CODEX_FEATURE_REMOTE_USER}}" "${command_path}" >> "${startup_log}" 2>&1 || true
        return
    fi

    "${command_path}" >> "${startup_log}" 2>&1 || true
}

start_runtime_hooks() {
    run_feature_command "${INSTALL_DIR}/link-folders.sh" "link-folders"
    run_feature_command "${INSTALL_DIR}/sync-config.sh" "sync-config"

    while :; do
        sleep 5
        run_feature_command "${INSTALL_DIR}/sync-config.sh" "sync-config" "quiet"
    done
}

(
    start_runtime_hooks
) &

if [ "$#" -eq 0 ]; then
    exec sleep infinity
fi

exec "$@"
