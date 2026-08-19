#!/usr/bin/env bash
set -euo pipefail

# Installed-feature contract: Node.js, npm, Codex, and their support files exist,
# and container startup does not run a blocking one-shot config sync.
node --version
npm --version
codex --version
test -x /usr/local/bin/node
test -x /usr/local/bin/npm
test -f /usr/local/share/codex-node/runtime.env
test -x /usr/local/share/codex-node/entrypoint.sh
! grep -Eq 'sync-config\.sh.*--once' /usr/local/share/codex-node/entrypoint.sh
test -x /usr/local/share/codex-node/link-folders.sh
test -x /usr/local/share/codex-node/sync-config.sh
test ! -e /usr/local/share/codex-node/options.env

# Watcher scenarios share bounded polling and cleanup so failures cannot leave a
# background process running in the test container.
tmp_dir="$(mktemp -d)"
watcher_pid=""
entrypoint_launcher_pid=""
entrypoint_session_pid=""
entrypoint_session_pid_file=""
entrypoint_sync_script="/usr/local/share/codex-node/sync-config.sh"

stop_watcher() {
    if [ -n "${watcher_pid}" ] && kill -0 "${watcher_pid}" 2>/dev/null; then
        kill -CONT "${watcher_pid}" 2>/dev/null || true
        kill "${watcher_pid}"
        wait "${watcher_pid}" 2>/dev/null || true
    fi
    watcher_pid=""
}

stop_entrypoint() {
    cleanup_session_pid="${entrypoint_session_pid}"

    if [ -z "${cleanup_session_pid}" ] && [ -n "${entrypoint_session_pid_file}" ] && [ -r "${entrypoint_session_pid_file}" ]; then
        cleanup_session_pid="$(cat "${entrypoint_session_pid_file}")"
    fi

    # Stop the payload, supervisor, runuser, watcher, and its current sleep together.
    case "${cleanup_session_pid}" in
        ''|*[!0-9]*)
            ;;
        *)
            kill -TERM "-${cleanup_session_pid}" 2>/dev/null || true
            sleep 0.1
            kill -KILL "-${cleanup_session_pid}" 2>/dev/null || true
            ;;
    esac

    if [ -n "${entrypoint_launcher_pid}" ]; then
        wait "${entrypoint_launcher_pid}" 2>/dev/null || true
    fi

    entrypoint_launcher_pid=""
    entrypoint_session_pid=""
}

cleanup() {
    stop_entrypoint
    stop_watcher
    rm -rf "${tmp_dir}"
}

fail() {
    echo "$*" >&2
    exit 1
}

assert_content() {
    file="$1"
    expected="$2"

    [ -f "${file}" ] || fail "Expected ${file} to exist."
    actual="$(cat "${file}")"
    [ "${actual}" = "${expected}" ] || fail "Unexpected content in ${file}: ${actual}"
}

wait_for_content() {
    file="$1"
    expected="$2"
    attempts=0

    while [ "${attempts}" -lt 15 ]; do
        if [ -f "${file}" ] && [ "$(cat "${file}")" = "${expected}" ]; then
            return 0
        fi
        if [ -n "${watcher_pid}" ] && ! kill -0 "${watcher_pid}" 2>/dev/null; then
            fail "Config watcher exited before updating ${file}."
        fi
        attempts=$((attempts + 1))
        sleep 1
    done

    fail "Timed out waiting for ${file} to contain: ${expected}"
}

wait_for_log() {
    log_file="$1"
    pattern="$2"
    attempts=0

    while [ "${attempts}" -lt 15 ]; do
        if [ -f "${log_file}" ] && grep -qi "${pattern}" "${log_file}"; then
            return 0
        fi
        if [ -n "${watcher_pid}" ] && ! kill -0 "${watcher_pid}" 2>/dev/null; then
            fail "Config watcher exited before logging ${pattern}."
        fi
        attempts=$((attempts + 1))
        sleep 1
    done

    fail "Timed out waiting for ${log_file} to mention ${pattern}."
}

wait_for_exact_log_line() {
    log_file="$1"
    expected_line="$2"
    attempts=0

    while [ "${attempts}" -lt 15 ]; do
        if [ -f "${log_file}" ] && grep -Fqx "${expected_line}" "${log_file}"; then
            return 0
        fi
        if [ -n "${watcher_pid}" ] && ! kill -0 "${watcher_pid}" 2>/dev/null; then
            fail "Config watcher exited before logging: ${expected_line}"
        fi
        attempts=$((attempts + 1))
        sleep 1
    done

    fail "Timed out waiting for ${log_file} to contain the line: ${expected_line}"
}

entrypoint_restart_count() {
    if [ ! -f /tmp/codex-config-sync.log ]; then
        printf '0\n'
        return 0
    fi

    restart_count="$(grep -Fc 'config sync watcher exited with status' /tmp/codex-config-sync.log 2>/dev/null || true)"
    printf '%s\n' "${restart_count:-0}"
}

entrypoint_timeout_count() {
    if [ ! -f /tmp/codex-startup.log ]; then
        printf '0\n'
        return 0
    fi

    timeout_count="$(grep -Fc 'config sync watcher did not become ready within 15 seconds; continuing startup while it retries' /tmp/codex-startup.log 2>/dev/null || true)"
    printf '%s\n' "${timeout_count:-0}"
}

entrypoint_watcher_pids() {
    for process_dir in /proc/[0-9]*; do
        [ -r "${process_dir}/stat" ] || continue
        [ -r "${process_dir}/cmdline" ] || continue

        process_group="$(awk '{ print $5 }' "${process_dir}/stat" 2>/dev/null || true)"
        [ -n "${process_group}" ] || continue
        [ "${process_group}" = "${entrypoint_session_pid}" ] || continue

        process_arguments="$(tr '\000' '\n' < "${process_dir}/cmdline" 2>/dev/null || true)"
        process_arg_1="$(printf '%s\n' "${process_arguments}" | sed -n '1p')"
        process_arg_2="$(printf '%s\n' "${process_arguments}" | sed -n '2p')"
        process_arg_3="$(printf '%s\n' "${process_arguments}" | sed -n '3p')"

        case "${process_arg_1}" in
            bash|*/bash) ;;
            *) continue ;;
        esac

        if [ "${process_arg_2}" = "${entrypoint_sync_script}" ] && [ "${process_arg_3}" = "--watch" ]; then
            printf '%s\n' "${process_dir#/proc/}"
        fi
    done
}

wait_for_single_entrypoint_watcher() {
    previous_watcher_pid="$1"
    attempts=0

    while [ "${attempts}" -lt 200 ]; do
        active_watcher_pids="$(entrypoint_watcher_pids)"
        active_watcher_count=0
        active_watcher_pid=""

        for process_pid in ${active_watcher_pids}; do
            active_watcher_count=$((active_watcher_count + 1))
            active_watcher_pid="${process_pid}"
        done

        if [ "${active_watcher_count}" -gt 1 ]; then
            echo "Entrypoint started concurrent config watchers: ${active_watcher_pids}" >&2
            return 1
        fi

        if [ "${active_watcher_count}" -eq 1 ] &&
            [ "${active_watcher_pid}" != "${previous_watcher_pid}" ] &&
            { [ -z "${previous_watcher_pid}" ] || ! kill -0 "${previous_watcher_pid}" 2>/dev/null; }; then
            printf '%s\n' "${active_watcher_pid}"
            return 0
        fi

        attempts=$((attempts + 1))
        sleep 0.1
    done

    echo "Expected exactly one active entrypoint config watcher." >&2
    return 1
}

assert_no_pid_file() {
    [ ! -e "$1/.config-sync.pid" ] || fail "Config sync unexpectedly created $1/.config-sync.pid."
}

trap cleanup EXIT INT TERM

workspace="${tmp_dir}/workspace"
codex_home="${tmp_dir}/home/.codex"

# With no link option configured, the helper is a no-op and does not create a
# Codex home as a side effect.
mkdir -p "${workspace}/.codex/sessions/project-a"
mkdir -p "${tmp_dir}/home"

CODEX_HOME="${codex_home}" \
HOME="${tmp_dir}/home" \
    /usr/local/share/codex-node/link-folders.sh

test ! -e "${codex_home}"

# Explicit CSV mappings create both links and mirror existing session directories
# into the archived-session tree.
csv_home="${tmp_dir}/csv-home/.codex"
CODEX_LINK_FOLDERS="sessions=${workspace}/.codex/sessions,archived_sessions=${workspace}/.codex/archived_sessions" \
CODEX_HOME="${csv_home}" \
HOME="${tmp_dir}/csv-home" \
    /usr/local/share/codex-node/link-folders.sh

test -L "${csv_home}/sessions"
test -L "${csv_home}/archived_sessions"
test "$(readlink "${csv_home}/sessions")" = "${workspace}/.codex/sessions"
test "$(readlink "${csv_home}/archived_sessions")" = "${workspace}/.codex/archived_sessions"
test -d "${workspace}/.codex/archived_sessions/project-a"

# A normal container user can reclaim and populate its conventional .codex home
# when image setup left that directory owned by root.
if [ "$(id -u)" = "0" ] && id vscode >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
    root_owned_home="${tmp_dir}/root-owned-home"
    root_owned_codex_home="${root_owned_home}/.codex"
    mkdir -p "${root_owned_codex_home}"
    chown root:root "${root_owned_codex_home}"

    sudo -u vscode env \
        CODEX_LINK_FOLDERS="sessions=${workspace}/.codex/sessions" \
        CODEX_HOME="${root_owned_codex_home}" \
        HOME="${root_owned_home}" \
        /usr/local/share/codex-node/link-folders.sh

    test -L "${root_owned_codex_home}/sessions"
    test "$(readlink "${root_owned_codex_home}/sessions")" = "${workspace}/.codex/sessions"
    test "$(stat -c '%U' "${root_owned_codex_home}")" = "vscode"
fi

# An explicitly empty link option remains a no-op for a home that does not exist.
disabled_home="${tmp_dir}/disabled-home/.codex"
CODEX_LINK_FOLDERS='' \
CODEX_HOME="${disabled_home}" \
HOME="${tmp_dir}/disabled-home" \
    /usr/local/share/codex-node/link-folders.sh

test ! -e "${disabled_home}"

# Even with linking disabled, an existing conventional home is made writable for
# the container user because Codex itself still needs that directory.
if [ "$(id -u)" = "0" ] && id vscode >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
    disabled_root_owned_home="${tmp_dir}/disabled-root-owned-home"
    disabled_root_owned_codex_home="${disabled_root_owned_home}/.codex"
    mkdir -p "${disabled_root_owned_codex_home}"
    chown root:root "${disabled_root_owned_home}" "${disabled_root_owned_codex_home}"

    sudo -u vscode env \
        CODEX_LINK_FOLDERS='' \
        CODEX_HOME="${disabled_root_owned_codex_home}" \
        HOME="${disabled_root_owned_home}" \
        /usr/local/share/codex-node/link-folders.sh

    test "$(stat -c '%U' "${disabled_root_owned_codex_home}")" = "vscode"
    test -w "${disabled_root_owned_codex_home}"
fi

# An absolute mapping creates a missing target directory before linking it.
absolute_home="${tmp_dir}/absolute-home/.codex"
test ! -e "${workspace}/state/sessions"
CODEX_LINK_FOLDERS="sessions=${workspace}/state/sessions" \
CODEX_HOME="${absolute_home}" \
HOME="${tmp_dir}/absolute-home" \
    /usr/local/share/codex-node/link-folders.sh

test -d "${workspace}/state/sessions"
test "$(readlink "${absolute_home}/sessions")" = "${workspace}/state/sessions"

# Relative targets are rejected so links cannot silently depend on process cwd.
relative_home="${tmp_dir}/relative-home/.codex"
if CODEX_LINK_FOLDERS='sessions=.codex/sessions' \
    CODEX_HOME="${relative_home}" \
    HOME="${tmp_dir}/relative-home" \
    /usr/local/share/codex-node/link-folders.sh; then
    echo "Expected relative Codex link target to fail." >&2
    exit 1
fi

# An empty sync option performs no filesystem work, while watch mode still emits
# its readiness token so entrypoint startup can continue.
disabled_config_home="${tmp_dir}/disabled-config-home/.codex"
CODEX_CONFIG_SYNC_SOURCE='' \
CODEX_HOME="${disabled_config_home}" \
HOME="${tmp_dir}/disabled-config-home" \
    /usr/local/share/codex-node/sync-config.sh

test ! -e "${disabled_config_home}"

disabled_ready_token="disabled-$$"
disabled_ready_log="${tmp_dir}/disabled-config-watch.log"
CODEX_CONFIG_SYNC_SOURCE='' \
CODEX_CONFIG_SYNC_READY_TOKEN="${disabled_ready_token}" \
CODEX_HOME="${disabled_config_home}" \
HOME="${tmp_dir}/disabled-config-home" \
    /usr/local/share/codex-node/sync-config.sh --watch > "${disabled_ready_log}" 2>&1

grep -Fqx "Codex config sync ready: ${disabled_ready_token}" "${disabled_ready_log}"
test ! -e "${disabled_config_home}"

# When only the source has content, initial reconciliation seeds the live config
# and completes without creating a legacy PID file.
source_seed_home="${tmp_dir}/source-seed-home/.codex"
source_seed="${tmp_dir}/source-seed.toml"
printf 'model = "source-seed"\n' > "${source_seed}"

CODEX_CONFIG_SYNC_SOURCE="${source_seed}" \
CODEX_HOME="${source_seed_home}" \
HOME="${tmp_dir}/source-seed-home" \
    /usr/local/share/codex-node/sync-config.sh

assert_content "${source_seed_home}/config.toml" 'model = "source-seed"'
assert_content "${source_seed}" 'model = "source-seed"'
assert_no_pid_file "${source_seed_home}"

# When the live config has content and the source is empty, live content wins;
# timestamps do not override the content-state rule.
live_seed_home="${tmp_dir}/live-seed-home/.codex"
live_seed_source="${tmp_dir}/live-seed.toml"
mkdir -p "${live_seed_home}"
printf 'model = "live-seed"\n' > "${live_seed_home}/config.toml"
touch -t 202001010101.01 "${live_seed_home}/config.toml"
: > "${live_seed_source}"
touch -t 202101010101.01 "${live_seed_source}"

CODEX_CONFIG_SYNC_SOURCE="${live_seed_source}" \
CODEX_HOME="${live_seed_home}" \
HOME="${tmp_dir}/live-seed-home" \
    /usr/local/share/codex-node/sync-config.sh --once

assert_content "${live_seed_source}" 'model = "live-seed"'
assert_content "${live_seed_home}/config.toml" 'model = "live-seed"'
assert_no_pid_file "${live_seed_home}"

# Atomic live updates must reject a config symlink instead of replacing it and
# disconnecting the managed target from future Codex writes.
live_symlink_home="${tmp_dir}/live-symlink-home/.codex"
live_symlink_target="${tmp_dir}/live-symlink-target.toml"
live_symlink_source="${tmp_dir}/live-symlink-source.toml"
live_symlink_log="${tmp_dir}/live-symlink.log"
mkdir -p "${live_symlink_home}"
: > "${live_symlink_target}"
ln -s "${live_symlink_target}" "${live_symlink_home}/config.toml"
printf 'model = "source-for-live-symlink"\n' > "${live_symlink_source}"

if CODEX_CONFIG_SYNC_SOURCE="${live_symlink_source}" \
    CODEX_HOME="${live_symlink_home}" \
    HOME="${tmp_dir}/live-symlink-home" \
    /usr/local/share/codex-node/sync-config.sh --once > "${live_symlink_log}" 2>&1; then
    fail 'Expected a symlinked live config to be rejected.'
fi

grep -Fq "live config '${live_symlink_home}/config.toml' is a symbolic link; use a regular container-local file." "${live_symlink_log}"
test -L "${live_symlink_home}/config.toml"
test "$(readlink "${live_symlink_home}/config.toml")" = "${live_symlink_target}"
test ! -s "${live_symlink_target}"
assert_content "${live_symlink_source}" 'model = "source-for-live-symlink"'
if find "${live_symlink_home}" -name '.config.toml.sync.*' -print | grep -q .; then
    fail 'Rejecting a symlinked live config left a temporary file behind.'
fi
assert_no_pid_file "${live_symlink_home}"

# Only the live path is restricted. A configured source symlink remains valid
# and is followed without replacing the link in either copy direction.
source_symlink_home="${tmp_dir}/source-symlink-home/.codex"
source_symlink_target="${tmp_dir}/source-symlink-target.toml"
source_symlink="${tmp_dir}/source-symlink.toml"
printf 'model = "source-through-link"\n' > "${source_symlink_target}"
ln -s "${source_symlink_target}" "${source_symlink}"

CODEX_CONFIG_SYNC_SOURCE="${source_symlink}" \
CODEX_HOME="${source_symlink_home}" \
HOME="${tmp_dir}/source-symlink-home" \
    /usr/local/share/codex-node/sync-config.sh --once

test -L "${source_symlink}"
test "$(readlink "${source_symlink}")" = "${source_symlink_target}"
assert_content "${source_symlink_home}/config.toml" 'model = "source-through-link"'

printf 'model = "live-through-source-link"\n' > "${source_symlink_home}/config.toml"
: > "${source_symlink_target}"
CODEX_CONFIG_SYNC_SOURCE="${source_symlink}" \
CODEX_HOME="${source_symlink_home}" \
HOME="${tmp_dir}/source-symlink-home" \
    /usr/local/share/codex-node/sync-config.sh --once

test -L "${source_symlink}"
assert_content "${source_symlink_target}" 'model = "live-through-source-link"'
assert_no_pid_file "${source_symlink_home}"

# One-shot sync leaves a missing source alone: it preserves local content and
# does not create the mapped source file.
missing_source_home="${tmp_dir}/missing-source-home/.codex"
missing_source="${tmp_dir}/missing-source/config.toml"
mkdir -p "${missing_source_home}" "$(dirname "${missing_source}")"
printf 'model = "keep-local"\n' > "${missing_source_home}/config.toml"

CODEX_CONFIG_SYNC_SOURCE="${missing_source}" \
CODEX_HOME="${missing_source_home}" \
HOME="${tmp_dir}/missing-source-home" \
    /usr/local/share/codex-node/sync-config.sh --once

test ! -e "${missing_source}"
assert_content "${missing_source_home}/config.toml" 'model = "keep-local"'
assert_no_pid_file "${missing_source_home}"

# A watcher also waits for a missing source. If it later appears with different
# content, neither side has precedence, so both files remain unchanged.
missing_source_log="${tmp_dir}/missing-source-watch.log"
CODEX_CONFIG_SYNC_SOURCE="${missing_source}" \
CODEX_HOME="${missing_source_home}" \
HOME="${tmp_dir}/missing-source-home" \
    /usr/local/share/codex-node/sync-config.sh --watch > "${missing_source_log}" 2>&1 &
watcher_pid=$!

wait_for_log "${missing_source_log}" 'watcher started'
test ! -e "${missing_source}"
assert_no_pid_file "${missing_source_home}"

printf 'model = "appeared-source"\n' > "${missing_source}"
wait_for_log "${missing_source_log}" 'conflict'
assert_content "${missing_source}" 'model = "appeared-source"'
assert_content "${missing_source_home}/config.toml" 'model = "keep-local"'
stop_watcher

# Once both files have an established baseline, a temporary source outage must
# not hide that the source alone changed when it returns.
known_source_home="${tmp_dir}/known-source-home/.codex"
known_source="${tmp_dir}/known-source/config.toml"
known_source_log="${tmp_dir}/known-source-watch.log"
mkdir -p "${known_source_home}" "$(dirname "${known_source}")"
printf 'model = "known-baseline"\n' > "${known_source_home}/config.toml"
printf 'model = "known-baseline"\n' > "${known_source}"

CODEX_CONFIG_SYNC_SOURCE="${known_source}" \
CODEX_HOME="${known_source_home}" \
HOME="${tmp_dir}/known-source-home" \
    /usr/local/share/codex-node/sync-config.sh --watch > "${known_source_log}" 2>&1 &
watcher_pid=$!

wait_for_log "${known_source_log}" 'watcher started'
mv "${known_source}" "${known_source}.absent"
wait_for_log "${known_source_log}" 'pausing without creating it'
test ! -e "${known_source}"

printf 'model = "source-after-absence"\n' > "${known_source}"
wait_for_content "${known_source_home}/config.toml" 'model = "source-after-absence"'
assert_content "${known_source}" 'model = "source-after-absence"'
kill -0 "${watcher_pid}"
if grep -qi 'conflict' "${known_source_log}"; then
    fail 'A known source returning with a one-sided edit caused a conflict.'
fi
stop_watcher

# The fault-injection harness replaces cksum and cmp only for this watcher. It
# can fail one operation or pause post-copy verification, making recovery and
# post-commit races deterministic without relying on timing sleeps.
race_bin="${tmp_dir}/race-bin"
race_home="${tmp_dir}/race-home/.codex"
race_source="${tmp_dir}/race-source.toml"
race_log="${tmp_dir}/race-watch.log"
race_mode="${tmp_dir}/race-mode"
race_release="${tmp_dir}/race-release"
# Each restart gets a new token so readiness must come from the current watcher.
race_ready_sequence=0
real_cmp="$(command -v cmp)"
real_cksum="$(command -v cksum)"
mkdir -p "${race_bin}" "${race_home}"

# This shim consumes one mode request and models a transient file-state failure.
cat > "${race_bin}/cksum" <<'EOF'
#!/usr/bin/env sh

# Removing the mode file ensures only one checksum attempt fails.
if [ -f "${SYNC_RACE_MODE}" ] && [ "$(cat "${SYNC_RACE_MODE}")" = "file-state-error" ]; then
    rm -f "${SYNC_RACE_MODE}"
    printf 'Config sync injected file-state error.\n' >&2
    exit 2
fi

exec "${SYNC_RACE_REAL_CKSUM}" "$@"
EOF

# This shim can fail one comparison or hold a selected post-copy comparison at
# a barrier while the test edits the opposite file.
cat > "${race_bin}/cmp" <<'EOF'
#!/usr/bin/env sh

wait_for_release() {
    # Consume the mode once, then wait until the test has made its competing edit.
    rm -f "${SYNC_RACE_MODE}"
    printf 'Config sync race %s paused.\n' "${race_direction}" >&2

    attempts=0
    while [ ! -e "${SYNC_RACE_RELEASE}" ] && [ "${attempts}" -lt 15 ]; do
        attempts=$((attempts + 1))
        sleep 1
    done

    [ -e "${SYNC_RACE_RELEASE}" ] || exit 2
}

left_path="${2-}"
right_path="${3-}"
race_direction=""
if [ -f "${SYNC_RACE_MODE}" ]; then
    race_direction="$(cat "${SYNC_RACE_MODE}")"
fi

if [ "${race_direction}" = "compare-error" ] && \
    [ "${left_path}" = "${SYNC_RACE_LOCAL}" ] && \
    [ "${right_path}" = "${SYNC_RACE_SOURCE}" ]; then
    rm -f "${SYNC_RACE_MODE}"
    printf 'Config sync injected compare error.\n' >&2
    exit 2
fi

if [ "${race_direction}" = "local-to-source" ] && \
    [ "${left_path}" = "${SYNC_RACE_LOCAL}" ] && \
    [ "${right_path}" = "${SYNC_RACE_SOURCE}" ] && \
    [ "$(cat "${left_path}")" = "$(cat "${right_path}")" ]; then
    wait_for_release
fi

"${SYNC_RACE_REAL_CMP}" "$@"
cmp_status=$?
[ "${cmp_status}" -eq 0 ] || exit "${cmp_status}"

if [ "${race_direction}" = "source-to-local" ] && \
    [ "${left_path}" = "${SYNC_RACE_SOURCE}" ] && \
    [ "${right_path}" = "${SYNC_RACE_LOCAL}" ]; then
    wait_for_release
fi
EOF
chmod +x "${race_bin}/cksum" "${race_bin}/cmp"

printf 'model = "race-seed"\n' > "${race_source}"

start_race_watcher() {
    race_ready_sequence=$((race_ready_sequence + 1))
    race_ready_token="race-$$-${race_ready_sequence}"
    PATH="${race_bin}:${PATH}" \
    SYNC_RACE_REAL_CMP="${real_cmp}" \
    SYNC_RACE_REAL_CKSUM="${real_cksum}" \
    SYNC_RACE_MODE="${race_mode}" \
    SYNC_RACE_RELEASE="${race_release}" \
    SYNC_RACE_LOCAL="${race_home}/config.toml" \
    SYNC_RACE_SOURCE="${race_source}" \
    CODEX_CONFIG_SYNC_SOURCE="${race_source}" \
    CODEX_CONFIG_SYNC_READY_TOKEN="${race_ready_token}" \
    CODEX_HOME="${race_home}" \
    HOME="${tmp_dir}/race-home" \
        /usr/local/share/codex-node/sync-config.sh --watch > "${race_log}" 2>&1 &
    watcher_pid=$!

    wait_for_exact_log_line "${race_log}" "Codex config sync ready: ${race_ready_token}"
    wait_for_log "${race_log}" 'watcher started'
}

# A transient checksum failure must not restart the watcher or discard its
# baseline; the pending local edit must still reach the source without conflict.
start_race_watcher
assert_content "${race_home}/config.toml" 'model = "race-seed"'

kill -STOP "${watcher_pid}"
printf 'model = "file-state-recovered"\n' > "${race_home}/config.toml"
printf 'file-state-error\n' > "${race_mode}"
kill -CONT "${watcher_pid}"
wait_for_log "${race_log}" 'injected file-state error'
kill -0 "${watcher_pid}" || fail 'Config watcher exited after a transient file-state error.'
wait_for_content "${race_source}" 'model = "file-state-recovered"'
if grep -qi 'conflict' "${race_log}"; then
    fail 'Config watcher reported a conflict after recovering from a file-state error.'
fi
stop_watcher

# A transient comparison failure has the same retry guarantee in the opposite
# direction: the pending source edit must still reach the live config.
start_race_watcher
kill -STOP "${watcher_pid}"
printf 'model = "compare-recovered"\n' > "${race_source}"
printf 'compare-error\n' > "${race_mode}"
kill -CONT "${watcher_pid}"
wait_for_log "${race_log}" 'injected compare error'
kill -0 "${watcher_pid}" || fail 'Config watcher exited after a transient compare error.'
wait_for_content "${race_home}/config.toml" 'model = "compare-recovered"'
if grep -qi 'conflict' "${race_log}"; then
    fail 'Config watcher reported a conflict after recovering from a compare error.'
fi
stop_watcher

# If the source changes just after a local-to-source commit, the watcher must
# advance to the committed baseline and apply that newer source edit next.
start_race_watcher
printf 'local-to-source\n' > "${race_mode}"
printf 'model = "race-local-copy"\n' > "${race_home}/config.toml"
wait_for_log "${race_log}" 'race local-to-source paused'
assert_content "${race_source}" 'model = "race-local-copy"'
printf 'model = "race-source-after-copy"\n' > "${race_source}"
: > "${race_release}"
wait_for_content "${race_home}/config.toml" 'model = "race-source-after-copy"'
wait_for_log "${race_log}" 'copied source to live config'
stop_watcher

# If the live config changes just after a source-to-local commit, the watcher
# must likewise preserve and propagate that newer local edit.
rm -f "${race_release}"
start_race_watcher
printf 'source-to-local\n' > "${race_mode}"
printf 'model = "race-source-copy"\n' > "${race_source}"
wait_for_log "${race_log}" 'race source-to-local paused'
assert_content "${race_home}/config.toml" 'model = "race-source-copy"'
printf 'model = "race-local-after-copy"\n' > "${race_home}/config.toml"
: > "${race_release}"
wait_for_content "${race_source}" 'model = "race-local-after-copy"'
wait_for_log "${race_log}" 'copied live config to source'

assert_no_pid_file "${race_home}"
stop_watcher

# Equal non-empty files are a no-op, including their modification times.
equal_home="${tmp_dir}/equal-home/.codex"
equal_source="${tmp_dir}/equal-source.toml"
mkdir -p "${equal_home}"
printf 'model = "equal"\n' > "${equal_source}"
printf 'model = "equal"\n' > "${equal_home}/config.toml"
touch -t 202001010101.01 "${equal_source}" "${equal_home}/config.toml"
equal_source_mtime="$(stat -c '%Y' "${equal_source}")"
equal_live_mtime="$(stat -c '%Y' "${equal_home}/config.toml")"

CODEX_CONFIG_SYNC_SOURCE="${equal_source}" \
CODEX_HOME="${equal_home}" \
HOME="${tmp_dir}/equal-home" \
    /usr/local/share/codex-node/sync-config.sh --once

test "$(stat -c '%Y' "${equal_source}")" = "${equal_source_mtime}"
test "$(stat -c '%Y' "${equal_home}/config.toml")" = "${equal_live_mtime}"
assert_no_pid_file "${equal_home}"

# On first reconciliation, different non-empty files have no known winner;
# report a conflict and preserve both contents unchanged.
initial_conflict_home="${tmp_dir}/initial-conflict-home/.codex"
initial_conflict_source="${tmp_dir}/initial-conflict-source.toml"
initial_conflict_log="${tmp_dir}/initial-conflict.log"
mkdir -p "${initial_conflict_home}"
printf 'model = "source-conflict"\n' > "${initial_conflict_source}"
printf 'model = "live-conflict"\n' > "${initial_conflict_home}/config.toml"

CODEX_CONFIG_SYNC_SOURCE="${initial_conflict_source}" \
CODEX_HOME="${initial_conflict_home}" \
HOME="${tmp_dir}/initial-conflict-home" \
    /usr/local/share/codex-node/sync-config.sh --once > "${initial_conflict_log}" 2>&1

assert_content "${initial_conflict_source}" 'model = "source-conflict"'
assert_content "${initial_conflict_home}/config.toml" 'model = "live-conflict"'
grep -qi 'conflict' "${initial_conflict_log}"
assert_no_pid_file "${initial_conflict_home}"

# A long-running watcher propagates one-sided edits in both directions, heals an
# emptied side, preserves simultaneous conflicts, and resumes afterward.
runtime_home="${tmp_dir}/runtime-home/.codex"
runtime_source="${tmp_dir}/runtime-source.toml"
runtime_log="${tmp_dir}/runtime-watch.log"
mkdir -p "${runtime_home}"
printf 'model = "runtime-seed"\n' > "${runtime_source}"
printf 'model = "runtime-seed"\n' > "${runtime_home}/config.toml"

CODEX_CONFIG_SYNC_SOURCE="${runtime_source}" \
CODEX_HOME="${runtime_home}" \
HOME="${tmp_dir}/runtime-home" \
    /usr/local/share/codex-node/sync-config.sh --watch > "${runtime_log}" 2>&1 &
watcher_pid=$!

attempts=0
while ! kill -0 "${watcher_pid}" 2>/dev/null; do
    attempts=$((attempts + 1))
    [ "${attempts}" -lt 5 ] || fail "Config watcher did not start."
    sleep 1
done
assert_no_pid_file "${runtime_home}"
wait_for_log "${runtime_log}" 'watcher started'

# A change on only one side propagates to the other side.
printf 'model = "runtime-local"\n' > "${runtime_home}/config.toml"
wait_for_content "${runtime_source}" 'model = "runtime-local"'

printf 'model = "runtime-source"\n' > "${runtime_source}"
wait_for_content "${runtime_home}/config.toml" 'model = "runtime-source"'

# An empty file is healed from the remaining non-empty copy in either direction.
: > "${runtime_home}/config.toml"
wait_for_content "${runtime_home}/config.toml" 'model = "runtime-source"'
assert_content "${runtime_source}" 'model = "runtime-source"'

: > "${runtime_source}"
wait_for_content "${runtime_source}" 'model = "runtime-source"'
assert_content "${runtime_home}/config.toml" 'model = "runtime-source"'

# Stop polling while both sides change so the watcher observes one simultaneous
# conflict and cannot infer a winner.
kill -STOP "${watcher_pid}"
printf 'model = "simultaneous-source"\n' > "${runtime_source}"
printf 'model = "simultaneous-live"\n' > "${runtime_home}/config.toml"
kill -CONT "${watcher_pid}"

wait_for_log "${runtime_log}" 'conflict'
assert_content "${runtime_source}" 'model = "simultaneous-source"'
assert_content "${runtime_home}/config.toml" 'model = "simultaneous-live"'
assert_no_pid_file "${runtime_home}"

# A later one-sided edit establishes a winner and resumes normal synchronization.
printf 'model = "source-after-conflict"\n' > "${runtime_source}"
wait_for_content "${runtime_home}/config.toml" 'model = "source-after-conflict"'
assert_content "${runtime_source}" 'model = "source-after-conflict"'

stop_watcher

# Start the installed entrypoint with a temporarily invalid source. Its watcher
# must fail and restart while the payload remains blocked behind readiness.
command -v setsid >/dev/null 2>&1 || fail "setsid is required for the entrypoint integration test."
entrypoint_case="${tmp_dir}/entrypoint"
entrypoint_home="${entrypoint_case}/home"
entrypoint_codex_home="${entrypoint_home}/.codex"
entrypoint_source="${entrypoint_case}/source.toml"
entrypoint_payload="${entrypoint_case}/payload.sh"
entrypoint_payload_ready="${entrypoint_case}/payload-ready"
entrypoint_payload_error="${entrypoint_case}/payload-error"
entrypoint_session_pid_file="${entrypoint_case}/session-pid"
entrypoint_output="${entrypoint_case}/entrypoint.log"
mkdir -p "${entrypoint_codex_home}" "${entrypoint_source}"
chmod 0755 "${tmp_dir}"
chmod 0777 "${entrypoint_case}" "${entrypoint_home}" "${entrypoint_codex_home}"

cat > "${entrypoint_payload}" <<'EOF'
#!/usr/bin/env sh
set -eu

if ! cmp -s "${CODEX_ENTRYPOINT_TEST_SOURCE}" "${CODEX_HOME}/config.toml"; then
    printf 'Payload started before initial config reconciliation.\n' > "${CODEX_ENTRYPOINT_TEST_ERROR_FILE}"
    exit 1
fi

: > "${CODEX_ENTRYPOINT_TEST_READY_FILE}"
exec sleep 300
EOF
chmod 0755 "${entrypoint_payload}"

# The test runner may have created the entrypoint's fixed logs as root before
# switching to the test user; permit this explicit second launch to append.
for entrypoint_log_file in /tmp/codex-startup.log /tmp/codex-config-sync.log; do
    if [ -e "${entrypoint_log_file}" ] && [ ! -w "${entrypoint_log_file}" ]; then
        [ ! -L "${entrypoint_log_file}" ] || fail "Refusing to chmod symlinked entrypoint log ${entrypoint_log_file}."
        sudo -n chmod a+rw "${entrypoint_log_file}" || fail "Could not make ${entrypoint_log_file} writable for the integration test."
    fi
done

restart_count_before="$(entrypoint_restart_count)"
CODEX_HOME="${entrypoint_codex_home}" \
CODEX_CONFIG_SYNC_SOURCE="${entrypoint_source}" \
CODEX_ENTRYPOINT_TEST_SOURCE="${entrypoint_source}" \
CODEX_ENTRYPOINT_TEST_READY_FILE="${entrypoint_payload_ready}" \
CODEX_ENTRYPOINT_TEST_ERROR_FILE="${entrypoint_payload_error}" \
CODEX_ENTRYPOINT_TEST_SESSION_PID_FILE="${entrypoint_session_pid_file}" \
    setsid sh -c 'printf "%s\n" "$$" > "${CODEX_ENTRYPOINT_TEST_SESSION_PID_FILE}"; exec "$@"' sh \
        /usr/local/share/codex-node/entrypoint.sh "${entrypoint_payload}" > "${entrypoint_output}" 2>&1 &
entrypoint_launcher_pid=$!

attempts=0
while :; do
    restart_count_after="$(entrypoint_restart_count)"
    if [ "${restart_count_after}" -gt "${restart_count_before}" ]; then
        break
    fi

    attempts=$((attempts + 1))
    if [ "${attempts}" -ge 100 ]; then
        cat "${entrypoint_output}" >&2
        fail "Entrypoint did not restart the failed config watcher."
    fi
    sleep 0.1
done

[ ! -e "${entrypoint_payload_ready}" ] || fail "Entrypoint payload started before config sync was ready."
[ ! -e "${entrypoint_payload_error}" ] || fail "Entrypoint payload observed an unreconciled config."

# Repairing the source lets the restarted watcher reconcile and release the payload.
rmdir "${entrypoint_source}"
printf 'model = "entrypoint-seed"\n' > "${entrypoint_source}"
chmod 0644 "${entrypoint_source}"

attempts=0
while [ ! -f "${entrypoint_payload_ready}" ]; do
    if [ -f "${entrypoint_payload_error}" ]; then
        cat "${entrypoint_payload_error}" >&2
        fail "Entrypoint payload observed an unreconciled config."
    fi

    attempts=$((attempts + 1))
    if [ "${attempts}" -ge 200 ]; then
        cat "${entrypoint_output}" >&2
        fail "Timed out waiting for the reconciled entrypoint payload."
    fi
    sleep 0.1
done

entrypoint_session_pid="$(cat "${entrypoint_session_pid_file}")"
case "${entrypoint_session_pid}" in
    ''|*[!0-9]*) fail "Entrypoint reported an invalid session PID." ;;
esac

# Only one watcher may remain. Killing it must produce one different watcher,
# proving the persistent supervisor handles runtime exits without overlap.
first_entrypoint_watcher_pid="$(wait_for_single_entrypoint_watcher "")"
sleep 1
stable_entrypoint_watcher_pid="$(wait_for_single_entrypoint_watcher "")"
[ "${stable_entrypoint_watcher_pid}" = "${first_entrypoint_watcher_pid}" ] ||
    fail "Entrypoint replaced a healthy config watcher."

restart_count_before="$(entrypoint_restart_count)"
kill -KILL "${first_entrypoint_watcher_pid}"
restarted_entrypoint_watcher_pid="$(wait_for_single_entrypoint_watcher "${first_entrypoint_watcher_pid}")"
[ "${restarted_entrypoint_watcher_pid}" != "${first_entrypoint_watcher_pid}" ] ||
    fail "Entrypoint did not restart the config watcher."
restart_count_after="$(entrypoint_restart_count)"
[ "${restart_count_after}" -gt "${restart_count_before}" ] ||
    fail "Entrypoint did not record the runtime watcher restart."

stop_entrypoint

# An invalid source can outlast the bounded readiness wait. In that case the
# payload starts after 15 seconds while the supervisor keeps retrying safely.
timeout_case="${tmp_dir}/entrypoint-timeout"
timeout_home="${timeout_case}/home"
timeout_codex_home="${timeout_home}/.codex"
timeout_source="${timeout_case}/source.toml"
timeout_payload="${timeout_case}/payload.sh"
timeout_payload_marker="${timeout_case}/payload-started-at"
entrypoint_session_pid_file="${timeout_case}/session-pid"
timeout_output="${timeout_case}/entrypoint.log"
mkdir -p "${timeout_codex_home}" "${timeout_source}"
chmod 0777 "${timeout_case}" "${timeout_home}" "${timeout_codex_home}"

cat > "${timeout_payload}" <<'EOF'
#!/usr/bin/env sh
set -eu

: > "${CODEX_ENTRYPOINT_TIMEOUT_MARKER}"
exec sleep 300
EOF
chmod 0755 "${timeout_payload}"

timeout_count_before="$(entrypoint_timeout_count)"
timeout_started_at="$(cut -d. -f1 /proc/uptime)"
CODEX_HOME="${timeout_codex_home}" \
CODEX_CONFIG_SYNC_SOURCE="${timeout_source}" \
CODEX_ENTRYPOINT_TIMEOUT_MARKER="${timeout_payload_marker}" \
CODEX_ENTRYPOINT_TEST_SESSION_PID_FILE="${entrypoint_session_pid_file}" \
    setsid sh -c 'printf "%s\n" "$$" > "${CODEX_ENTRYPOINT_TEST_SESSION_PID_FILE}"; exec "$@"' sh \
        /usr/local/share/codex-node/entrypoint.sh "${timeout_payload}" > "${timeout_output}" 2>&1 &
entrypoint_launcher_pid=$!

attempts=0
while :; do
    timeout_count_after="$(entrypoint_timeout_count)"
    if [ "${timeout_count_after}" -gt "${timeout_count_before}" ]; then
        break
    fi

    [ ! -e "${timeout_payload_marker}" ] || fail "Entrypoint payload started before the readiness timeout was logged."
    attempts=$((attempts + 1))
    if [ "${attempts}" -ge 250 ]; then
        cat "${timeout_output}" >&2
        fail "Entrypoint did not continue after its bounded readiness wait."
    fi
    sleep 0.1
done

timeout_finished_at="$(cut -d. -f1 /proc/uptime)"
timeout_elapsed=$((timeout_finished_at - timeout_started_at))
[ "${timeout_elapsed}" -ge 15 ] || fail "Entrypoint logged the readiness timeout before 15 seconds elapsed."

attempts=0
while [ ! -f "${timeout_payload_marker}" ]; do
    attempts=$((attempts + 1))
    [ "${attempts}" -lt 50 ] || fail "Entrypoint logged the readiness timeout but did not start its payload."
    sleep 0.1
done
test ! -e "${timeout_codex_home}/config.toml"

entrypoint_session_pid="$(cat "${entrypoint_session_pid_file}")"
case "${entrypoint_session_pid}" in
    ''|*[!0-9]*) fail "Timed-out entrypoint reported an invalid session PID." ;;
esac

# The payload is running, but synchronization must remain supervised in the background.
restart_count_before="$(entrypoint_restart_count)"
attempts=0
while :; do
    kill -0 "${entrypoint_session_pid}" 2>/dev/null || fail "Entrypoint payload exited after the readiness timeout."
    restart_count_after="$(entrypoint_restart_count)"
    if [ "${restart_count_after}" -gt "${restart_count_before}" ]; then
        break
    fi

    attempts=$((attempts + 1))
    [ "${attempts}" -lt 50 ] || fail "Config supervisor stopped retrying after the readiness timeout."
    sleep 0.1
done

stop_entrypoint
