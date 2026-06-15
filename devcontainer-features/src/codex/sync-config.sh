#!/usr/bin/env bash
set -euo pipefail

script_path="${BASH_SOURCE[0]}"
INSTALL_DIR="/usr/local/share/codex"
codex_config_sync_source_from_env="${CODEX_CONFIG_SYNC_SOURCE-}"

if [ -f "${INSTALL_DIR}/options.env" ]; then
    # shellcheck disable=SC1091
    . "${INSTALL_DIR}/options.env"
fi

if [ -n "${codex_config_sync_source_from_env}" ]; then
    config_sync_source="${codex_config_sync_source_from_env}"
else
    config_sync_source="${CODEX_CONFIG_SYNC_SOURCE-}"
fi

if [ -z "${config_sync_source}" ]; then
    exit 0
fi

if [[ "${config_sync_source}" != /* ]]; then
    echo "Invalid Codex config sync source: '${config_sync_source}'. Use an absolute path." >&2
    exit 1
fi

codex_home="${CODEX_HOME:-${HOME}/.codex}"
local_config="${codex_home}/config.toml"
pid_file="${codex_home}/.config-sync.pid"

copy_if_different() {
    local src="$1"
    local dst="$2"

    if [ -f "${src}" ] && { [ ! -f "${dst}" ] || ! cmp -s "${src}" "${dst}"; }; then
        mkdir -p "$(dirname "${dst}")"
        cp "${src}" "${dst}"
    fi
}

mtime() {
    if [ -f "$1" ]; then
        stat -c '%Y' "$1"
    else
        printf '0\n'
    fi
}

hash_file() {
    if [ -f "$1" ]; then
        cksum "$1"
    else
        printf 'missing\n'
    fi
}

sync_newest_once() {
    mkdir -p "${codex_home}" "$(dirname "${config_sync_source}")"
    [ -f "${config_sync_source}" ] || : > "${config_sync_source}"

    local local_mtime source_mtime
    local_mtime="$(mtime "${local_config}")"
    source_mtime="$(mtime "${config_sync_source}")"

    if [ "${local_mtime}" -gt "${source_mtime}" ]; then
        copy_if_different "${local_config}" "${config_sync_source}"
    else
        copy_if_different "${config_sync_source}" "${local_config}"
    fi
}

watch_config() {
    local last_local_hash=""
    local last_source_hash=""

    while :; do
        local current_local_hash current_source_hash
        local local_changed=false
        local source_changed=false

        current_local_hash="$(hash_file "${local_config}")"
        current_source_hash="$(hash_file "${config_sync_source}")"

        if [ "${current_local_hash}" != "${last_local_hash}" ]; then
            local_changed=true
        fi

        if [ "${current_source_hash}" != "${last_source_hash}" ]; then
            source_changed=true
        fi

        if [ "${local_changed}" = true ] && [ "${source_changed}" = true ]; then
            local local_mtime source_mtime
            local_mtime="$(mtime "${local_config}")"
            source_mtime="$(mtime "${config_sync_source}")"

            if [ "${local_mtime}" -ge "${source_mtime}" ]; then
                copy_if_different "${local_config}" "${config_sync_source}"
            else
                copy_if_different "${config_sync_source}" "${local_config}"
            fi
        elif [ "${local_changed}" = true ]; then
            copy_if_different "${local_config}" "${config_sync_source}"
        elif [ "${source_changed}" = true ]; then
            copy_if_different "${config_sync_source}" "${local_config}"
        fi

        last_local_hash="$(hash_file "${local_config}")"
        last_source_hash="$(hash_file "${config_sync_source}")"

        sleep 2
    done
}

watcher_running() {
    local candidate_pid="$1"
    local args

    case "${candidate_pid}" in
        ''|*[!0-9]*)
            return 1
            ;;
    esac

    if ! kill -0 "${candidate_pid}" 2>/dev/null; then
        return 1
    fi

    args="$(ps -p "${candidate_pid}" -o args= 2>/dev/null || true)"
    case "${args}" in
        *sync-config.sh*--watch*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

start_watcher() {
    if [ -f "${pid_file}" ]; then
        local old_pid
        old_pid="$(cat "${pid_file}" 2>/dev/null || true)"
        if watcher_running "${old_pid}"; then
            return
        fi
        rm -f "${pid_file}"
    fi

    if command -v setsid >/dev/null 2>&1; then
        CODEX_CONFIG_SYNC_SOURCE="${config_sync_source}" setsid "${script_path}" --watch </dev/null >/tmp/codex-config-sync.log 2>&1 &
    else
        CODEX_CONFIG_SYNC_SOURCE="${config_sync_source}" nohup "${script_path}" --watch </dev/null >/tmp/codex-config-sync.log 2>&1 &
    fi

    printf '%s\n' "$!" > "${pid_file}"
}

if [ "${1-}" = "--watch" ]; then
    watch_config
    exit 0
fi

sync_newest_once
start_watcher
