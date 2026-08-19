#!/usr/bin/env bash
set -euo pipefail

# Keep a host-mounted config and Codex's live config synchronized without ever
# using empty or missing content to erase a non-empty file.
INSTALL_DIR="/usr/local/share/codex-node"
# Capture the invocation value before loading persisted feature options so a
# non-empty runtime override wins over the image's build-time configuration.
codex_config_sync_source_from_env="${CODEX_CONFIG_SYNC_SOURCE-}"
config_sync_ready_token="${CODEX_CONFIG_SYNC_READY_TOKEN-}"

if [ -f "${INSTALL_DIR}/options.env" ]; then
    # shellcheck disable=SC1091
    . "${INSTALL_DIR}/options.env"
fi

if [ -n "${codex_config_sync_source_from_env}" ]; then
    config_sync_source="${codex_config_sync_source_from_env}"
else
    config_sync_source="${CODEX_CONFIG_SYNC_SOURCE-}"
fi

log_sync() {
    printf 'Codex config sync: %s\n' "$*" >&2
}

signal_config_sync_ready() {
    # The entrypoint recognizes this token as successful initial reconciliation
    # and waits for it up to its bounded startup timeout.
    if [ -z "${config_sync_ready_token}" ]; then
        return 0
    fi

    printf 'Codex config sync ready: %s\n' "${config_sync_ready_token}" >&2
}

if [ -z "${config_sync_source}" ]; then
    # Sync is optional, but a supervising entrypoint still needs its readiness
    # acknowledgement when the option is disabled.
    signal_config_sync_ready
    exit 0
fi

if [[ "${config_sync_source}" != /* ]]; then
    echo "Invalid Codex config sync source: '${config_sync_source}'. Use an absolute path." >&2
    exit 1
fi

codex_home="${CODEX_HOME:-${HOME}/.codex}"
local_config="${codex_home}/config.toml"
# Snapshots and newly created configs may contain credentials.
umask 077

# reconcile_once reports its final pair of states through these globals so a
# long-running watcher can establish its initial direction baseline.
reconciled_local_state=""
reconciled_source_state=""

# Describe a path as missing, empty, or non-empty content plus a checksum. A
# broken symlink is deliberately treated as an invalid file, not as missing.
file_state() {
    local path="$1"
    local checksum

    if [ ! -e "${path}" ] && [ ! -L "${path}" ]; then
        printf 'missing\n'
        return 0
    fi

    if [ ! -f "${path}" ]; then
        log_sync "'${path}' exists but is not a regular file."
        return 1
    fi

    if [ ! -r "${path}" ]; then
        log_sync "'${path}' is not readable."
        return 1
    fi

    if [ ! -s "${path}" ]; then
        printf 'empty\n'
        return 0
    fi

    if ! checksum="$(cksum < "${path}")"; then
        log_sync "failed to checksum '${path}'."
        return 1
    fi

    printf 'content:%s\n' "${checksum}"
}

# Atomic source-to-live updates replace the destination directory entry. Reject
# a live symlink so a successful sync can never silently sever that link.
validate_local_config_path() {
    if [ -L "${local_config}" ]; then
        log_sync "live config '${local_config}' is a symbolic link; use a regular container-local file."
        return 1
    fi

    return 0
}

local_file_state() {
    validate_local_config_path || return 1

    file_state "${local_config}"
}

is_content_state() {
    case "$1" in
        content:*) return 0 ;;
        *) return 1 ;;
    esac
}

compare_files() {
    local left="$1"
    local right="$2"
    local status

    if cmp -s "${left}" "${right}"; then
        printf 'equal\n'
        return 0
    else
        status="$?"
    fi

    # cmp uses status 1 for an ordinary content difference and values above 1
    # for an observation error that should be retried.
    if [ "${status}" -eq 1 ]; then
        printf 'different\n'
        return 0
    fi

    log_sync "failed to compare '${left}' and '${right}'."
    return 1
}

# A copy returns nonzero only before the destination commit. After mv or cp
# succeeds it returns zero, even if verification observes a newer edit, so the
# watcher advances to the committed baseline and handles that edit next.
# Source-to-live updates stage beside the destination so the final rename is
# atomic on the live config's filesystem.
copy_source_to_local() {
    local expected_source_state="$1"
    local expected_local_state="$2"
    local temporary_config snapshot_state current_source_state current_local_state comparison

    mkdir -p "${codex_home}"
    if ! temporary_config="$(mktemp "${codex_home}/.config.toml.sync.XXXXXX")"; then
        log_sync "failed to create a temporary file beside '${local_config}'."
        return 1
    fi

    # Snapshot first; never copy directly from a file that may be changing.
    if ! cp "${config_sync_source}" "${temporary_config}"; then
        rm -f "${temporary_config}"
        log_sync "failed to snapshot source '${config_sync_source}'."
        return 1
    fi

    if ! snapshot_state="$(file_state "${temporary_config}")" || [ "${snapshot_state}" != "${expected_source_state}" ]; then
        rm -f "${temporary_config}"
        log_sync "source '${config_sync_source}' changed while it was being read; retrying later."
        return 1
    fi

    # Recheck both inputs immediately before commit. If either moved from the
    # caller's expected state, leave the destination untouched and retry.
    if ! current_source_state="$(file_state "${config_sync_source}")" ||
        ! current_local_state="$(local_file_state)"; then
        rm -f "${temporary_config}"
        return 1
    fi

    if [ "${current_source_state}" != "${expected_source_state}" ] ||
        [ "${current_local_state}" != "${expected_local_state}" ]; then
        rm -f "${temporary_config}"
        log_sync "a config changed before the live update; retrying later."
        return 1
    fi

    if ! comparison="$(compare_files "${config_sync_source}" "${temporary_config}")"; then
        rm -f "${temporary_config}"
        return 1
    fi
    if [ "${comparison}" != "equal" ]; then
        rm -f "${temporary_config}"
        log_sync "source '${config_sync_source}' changed while it was being read; retrying later."
        return 1
    fi

    if ! validate_local_config_path; then
        rm -f "${temporary_config}"
        return 1
    fi

    # The temporary file is in codex_home, so this rename is one atomic commit.
    if ! mv -f "${temporary_config}" "${local_config}"; then
        rm -f "${temporary_config}"
        log_sync "failed to replace live config '${local_config}'."
        return 1
    fi

    # A post-commit mismatch means another edit won a later race. The commit is
    # still valid; the watcher will observe and reconcile that edit next.
    if ! comparison="$(compare_files "${config_sync_source}" "${local_config}")"; then
        log_sync "live config was replaced, but the update could not be verified; checking again later."
        return 0
    fi
    if [ "${comparison}" != "equal" ]; then
        log_sync "source changed after updating '${local_config}'; checking again later."
        return 0
    fi

    log_sync "copied source to live config."
    return 0
}

copy_local_to_source() {
    local expected_local_state="$1"
    local expected_source_state="$2"
    local temporary_config snapshot_state current_local_state current_source_state comparison

    # Mounted source files may not support an atomic rename from a local temp
    # file, so snapshot locally, validate, and commit with cp.
    if ! temporary_config="$(mktemp "${TMPDIR:-/tmp}/codex-config-sync.XXXXXX")"; then
        log_sync "failed to create a temporary config snapshot."
        return 1
    fi

    if ! cp "${local_config}" "${temporary_config}"; then
        rm -f "${temporary_config}"
        log_sync "failed to snapshot live config '${local_config}'."
        return 1
    fi

    if ! snapshot_state="$(file_state "${temporary_config}")" || [ "${snapshot_state}" != "${expected_local_state}" ]; then
        rm -f "${temporary_config}"
        log_sync "live config '${local_config}' changed while it was being read; retrying later."
        return 1
    fi

    # Protect both sides with optimistic state checks before overwriting the
    # mounted source.
    if ! current_local_state="$(local_file_state)" ||
        ! current_source_state="$(file_state "${config_sync_source}")"; then
        rm -f "${temporary_config}"
        return 1
    fi

    if [ "${current_local_state}" != "${expected_local_state}" ] ||
        [ "${current_source_state}" != "${expected_source_state}" ]; then
        rm -f "${temporary_config}"
        log_sync "a config changed before the source update; retrying later."
        return 1
    fi

    if ! comparison="$(compare_files "${local_config}" "${temporary_config}")"; then
        rm -f "${temporary_config}"
        return 1
    fi
    if [ "${comparison}" != "equal" ]; then
        rm -f "${temporary_config}"
        log_sync "live config '${local_config}' changed while it was being read; retrying later."
        return 1
    fi

    if ! validate_local_config_path; then
        rm -f "${temporary_config}"
        return 1
    fi

    # This is the commit point for the live-to-source direction.
    if ! cp "${temporary_config}" "${config_sync_source}"; then
        rm -f "${temporary_config}"
        log_sync "failed to update source '${config_sync_source}'."
        return 1
    fi

    if ! comparison="$(compare_files "${temporary_config}" "${config_sync_source}")"; then
        rm -f "${temporary_config}"
        log_sync "source was updated, but the snapshot could not be verified; checking again later."
        return 0
    fi
    if [ "${comparison}" != "equal" ]; then
        rm -f "${temporary_config}"
        log_sync "source changed after it was updated; checking again later."
        return 0
    fi

    if ! comparison="$(compare_files "${local_config}" "${config_sync_source}")"; then
        rm -f "${temporary_config}"
        log_sync "source was updated, but the live config could not be verified; checking again later."
        return 0
    fi
    if [ "${comparison}" != "equal" ]; then
        rm -f "${temporary_config}"
        log_sync "live config changed after the source was updated; checking again later."
        return 0
    fi

    rm -f "${temporary_config}"
    log_sync "copied live config to source."
    return 0
}

log_conflict() {
    # With no trustworthy direction signal, preserving both files is safer than
    # guessing a winner from timestamps.
    printf "Codex config sync conflict: '%s' and '%s' contain different non-empty content; leaving both unchanged.\n" \
        "${local_config}" "${config_sync_source}" >&2
}

reconcile_once() {
    local local_state source_state comparison

    if ! local_state="$(local_file_state)" ||
        ! source_state="$(file_state "${config_sync_source}")"; then
        return 1
    fi

    reconciled_local_state="${local_state}"
    reconciled_source_state="${source_state}"

    # A configured mount may appear after startup; never create its source path
    # from inside the container while it is absent.
    if [ "${source_state}" = "missing" ]; then
        log_sync "source '${config_sync_source}' is missing; waiting without creating it."
        return 0
    fi

    # Without a prior baseline, only a non-empty/empty relationship supplies a
    # safe direction. Different non-empty files remain an explicit conflict.
    if is_content_state "${source_state}"; then
        if ! is_content_state "${local_state}"; then
            if copy_source_to_local "${source_state}" "${local_state}"; then
                reconciled_local_state="${source_state}"
                reconciled_source_state="${source_state}"
            else
                return 1
            fi
        else
            comparison="$(compare_files "${config_sync_source}" "${local_config}")" || return 1
            if [ "${comparison}" = "different" ]; then
                log_conflict
            fi
        fi
    elif is_content_state "${local_state}"; then
        if copy_local_to_source "${local_state}" "${source_state}"; then
            reconciled_local_state="${local_state}"
            reconciled_source_state="${local_state}"
        else
            return 1
        fi
    fi
}

watch_config() {
    local last_local_state last_source_state
    local current_local_state current_source_state
    local comparison source_is_absent

    # Initial reconciliation must succeed before recording a baseline or
    # signalling readiness to the entrypoint.
    if ! reconcile_once; then
        return 1
    fi
    last_local_state="${reconciled_local_state}"
    last_source_state="${reconciled_source_state}"
    if [ "${last_source_state}" = "missing" ]; then
        source_is_absent="true"
    else
        source_is_absent="false"
    fi

    printf "Codex config sync watcher started: '%s' <-> '%s'.\n" \
        "${local_config}" "${config_sync_source}" >&2

    if ! signal_config_sync_ready; then
        return 1
    fi

    while :; do
        sleep 2

        # Observation failures are retryable. Keeping this process alive also
        # keeps the last known states needed to infer the next edit direction.
        if ! current_local_state="$(local_file_state)" ||
            ! current_source_state="$(file_state "${config_sync_source}")"; then
            continue
        fi

        # Track a runtime outage separately so it does not erase a trustworthy
        # source baseline used to identify edits when the file returns.
        if [ "${current_source_state}" = "missing" ]; then
            if [ "${source_is_absent}" = "false" ]; then
                log_sync "source '${config_sync_source}' is missing; pausing without creating it."
            fi
            source_is_absent="true"
            continue
        fi

        if [ "${source_is_absent}" = "true" ]; then
            if [ "${last_source_state}" = "missing" ]; then
                # A source missing from initial reconciliation has no baseline,
                # so its first appearance still needs direction-neutral handling.
                if reconcile_once; then
                    last_local_state="${reconciled_local_state}"
                    last_source_state="${reconciled_source_state}"
                    source_is_absent="false"
                fi
                continue
            fi
            source_is_absent="false"
        fi

        # Equal state tokens keep the idle path read-only and avoid rewriting
        # unchanged files.
        if [ "${current_local_state}" = "${last_local_state}" ] && [ "${current_source_state}" = "${last_source_state}" ]; then
            continue
        fi

        # Empty content never wins over non-empty content. When both sides have
        # content, the unchanged baseline identifies a one-sided edit.
        if is_content_state "${current_local_state}" && [ "${current_source_state}" = "empty" ]; then
            if ! copy_local_to_source "${current_local_state}" "${current_source_state}"; then
                continue
            fi
            current_source_state="${current_local_state}"
        elif is_content_state "${current_source_state}" && ! is_content_state "${current_local_state}"; then
            if ! copy_source_to_local "${current_source_state}" "${current_local_state}"; then
                continue
            fi
            current_local_state="${current_source_state}"
        elif is_content_state "${current_local_state}" && is_content_state "${current_source_state}"; then
            comparison="$(compare_files "${local_config}" "${config_sync_source}")" || continue
            if [ "${comparison}" = "different" ]; then
                if [ "${current_local_state}" != "${last_local_state}" ] && [ "${current_source_state}" = "${last_source_state}" ]; then
                    if ! copy_local_to_source "${current_local_state}" "${current_source_state}"; then
                        continue
                    fi
                    current_source_state="${current_local_state}"
                elif [ "${current_source_state}" != "${last_source_state}" ] && [ "${current_local_state}" = "${last_local_state}" ]; then
                    if ! copy_source_to_local "${current_source_state}" "${current_local_state}"; then
                        continue
                    fi
                    current_local_state="${current_source_state}"
                else
                    log_conflict
                fi
            fi
        fi

        # Advance only after this observation has been handled. Failed copies
        # continue above and retain the previous trustworthy baseline.
        last_local_state="${current_local_state}"
        last_source_state="${current_source_state}"
    done
}

# --once supports initialization and diagnostics; --watch performs that same
# reconciliation and then keeps the checksum baseline in memory.
if [ "$#" -gt 1 ]; then
    echo "Usage: ${0##*/} [--once|--watch]" >&2
    exit 2
fi

mode="${1-}"
if [ -z "${mode}" ]; then
    mode="--once"
fi

case "${mode}" in
    --once)
        reconcile_once
        ;;
    --watch)
        watch_config
        ;;
    *)
        echo "Usage: ${0##*/} [--once|--watch]" >&2
        exit 2
        ;;
esac
