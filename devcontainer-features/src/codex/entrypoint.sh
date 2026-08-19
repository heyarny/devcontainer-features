#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/usr/local/share/codex"
runtime_env_file="${INSTALL_DIR}/runtime.env"
startup_log="/tmp/codex-startup.log"
sync_log="/tmp/codex-config-sync.log"

# Load the remote-user identity that the installer resolved for this container.
if [ -f "${runtime_env_file}" ]; then
    # shellcheck disable=SC1090
    . "${runtime_env_file}"
fi

# Readiness is an internal handshake, so never trust a token inherited from the caller.
unset CODEX_CONFIG_SYNC_READY_TOKEN

# Run hooks as the remote user when possible so their files are not owned by root.
run_feature_command() {
    local command_path="$1"
    local command_name="$2"
    local log_mode="${3:-normal}"
    local output_log="${4:-${startup_log}}"
    local remote_home=""
    shift 4

    if [ "${log_mode}" != "quiet" ]; then
        printf '[%s] starting %s as uid=%s user=%s\n' "$(date -Iseconds)" "${command_name}" "$(id -u)" "$(id -un)" >> "${output_log}"
    fi

    if [ ! -x "${command_path}" ]; then
        printf '[%s] %s is not executable\n' "$(date -Iseconds)" "${command_path}" >> "${output_log}"
        return 1
    fi

    if [ "$(id -u)" = "0" ] && [ -n "${CODEX_FEATURE_REMOTE_USER:-}" ] && [ "${CODEX_FEATURE_REMOTE_USER}" != "root" ] && id "${CODEX_FEATURE_REMOTE_USER}" >/dev/null 2>&1 && command -v runuser >/dev/null 2>&1; then
        remote_home="${CODEX_FEATURE_REMOTE_USER_HOME:-}"
        # Account lookup covers images whose home is not /home/<user>.
        if [ -z "${remote_home}" ] && command -v getent >/dev/null 2>&1; then
            remote_home="$(getent passwd "${CODEX_FEATURE_REMOTE_USER}" | cut -d: -f6 || true)"
        fi

        if [ "${log_mode}" != "quiet" ]; then
            printf '[%s] running %s as %s with HOME=%s\n' "$(date -Iseconds)" "${command_name}" "${CODEX_FEATURE_REMOTE_USER}" "${remote_home:-/home/${CODEX_FEATURE_REMOTE_USER}}" >> "${output_log}"
        fi
        runuser -u "${CODEX_FEATURE_REMOTE_USER}" -- env \
            HOME="${remote_home:-/home/${CODEX_FEATURE_REMOTE_USER}}" \
            CODEX_CONFIG_SYNC_READY_TOKEN="${CODEX_CONFIG_SYNC_READY_TOKEN-}" \
            "${command_path}" "$@" >> "${output_log}" 2>&1
        return
    fi

    # Keep the current identity when already unprivileged or no valid user switch exists.
    "${command_path}" "$@" >> "${output_log}" 2>&1
}

run_initial_hooks() {
    # Linking errors are logged but must not prevent the user's main command from starting.
    if ! run_feature_command "${INSTALL_DIR}/link-folders.sh" "link-folders" "normal" "${startup_log}"; then
        printf '[%s] link-folders failed; continuing container startup\n' "$(date -Iseconds)" >> "${startup_log}"
    fi
}

# Run one watcher at a time and restart it only after a nonzero exit.
supervise_config_sync() {
    local watcher_status

    while :; do
        if run_feature_command "${INSTALL_DIR}/sync-config.sh" "sync-config --watch" "quiet" "${sync_log}" --watch; then
            # A clean exit means synchronization is disabled, so no restart is needed.
            return 0
        else
            watcher_status="$?"
        fi

        printf '[%s] config sync watcher exited with status %s; restarting\n' "$(date -Iseconds)" "${watcher_status}" >> "${sync_log}"
        sleep 1
    done
}

start_config_sync() {
    local ready_token supervisor_pid sync_ready=false
    local attempts=0

    # A per-launch token prevents an old ready line in the append-only log from matching.
    ready_token="${BASHPID}-${RANDOM}-${RANDOM}"

    (
        export CODEX_CONFIG_SYNC_READY_TOKEN="${ready_token}"
        supervise_config_sync
    ) &
    supervisor_pid="$!"

    # Allow initial reconciliation up to 15 seconds without blocking startup indefinitely.
    while [ "${attempts}" -lt 150 ]; do
        if grep -Fqx "Codex config sync ready: ${ready_token}" "${sync_log}" 2>/dev/null; then
            sync_ready=true
            break
        fi

        if ! kill -0 "${supervisor_pid}" 2>/dev/null; then
            break
        fi

        attempts=$((attempts + 1))
        sleep 0.1
    done

    # Close the race where readiness is logged during the loop's final sleep.
    if [ "${sync_ready}" = false ] &&
        grep -Fqx "Codex config sync ready: ${ready_token}" "${sync_log}" 2>/dev/null; then
        sync_ready=true
    fi

    if [ "${sync_ready}" = true ]; then
        printf '[%s] config sync watcher initialized\n' "$(date -Iseconds)" >> "${startup_log}"
    elif kill -0 "${supervisor_pid}" 2>/dev/null; then
        printf '[%s] config sync watcher did not become ready within 15 seconds; continuing startup while it retries\n' \
            "$(date -Iseconds)" >> "${startup_log}"
    else
        printf '[%s] config sync supervisor exited before becoming ready; continuing container startup\n' \
            "$(date -Iseconds)" >> "${startup_log}"
    fi
}

run_initial_hooks
start_config_sync

# Keep a commandless container alive; otherwise hand PID 1 directly to the requested command.
if [ "$#" -eq 0 ]; then
    exec sleep infinity
fi

exec "$@"
