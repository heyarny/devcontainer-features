#!/usr/bin/env sh
set -eu

codex --version
test -x /usr/local/bin/codex
test -L /usr/local/bin/codex
test -d /usr/local/share/codex/packages/standalone
test -x /usr/local/share/codex/link-folders.sh
test -x /usr/local/share/codex/sync-config.sh
test ! -e /usr/local/share/codex/options.env

if id vscode >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
    sudo -u vscode codex --version
fi

if id node >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
    sudo -u node codex --version
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

workspace="${tmp_dir}/workspace"
codex_home="${tmp_dir}/home/.codex"

if [ "$(id -u)" = "0" ] && id vscode >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
    root_owned_home="${tmp_dir}/root-owned-home"
    root_owned_codex_home="${root_owned_home}/.codex"
    mkdir -p "${root_owned_codex_home}"
    chown root:root "${root_owned_home}" "${root_owned_codex_home}"

    sudo -u vscode env \
        CODEX_LINK_FOLDERS='' \
        CODEX_HOME="${root_owned_codex_home}" \
        HOME="${root_owned_home}" \
        /usr/local/share/codex/link-folders.sh

    test "$(stat -c '%U' "${root_owned_codex_home}")" = "vscode"
    test -w "${root_owned_codex_home}"
fi

mkdir -p "${workspace}/.codex/sessions/project-a" "${tmp_dir}/home"

CODEX_LINK_FOLDERS="sessions=${workspace}/.codex/sessions,archived_sessions=${workspace}/.codex/archived_sessions" \
CODEX_HOME="${codex_home}" \
HOME="${tmp_dir}/home" \
    /usr/local/share/codex/link-folders.sh

test -L "${codex_home}/sessions"
test -L "${codex_home}/archived_sessions"
test "$(readlink "${codex_home}/sessions")" = "${workspace}/.codex/sessions"
test "$(readlink "${codex_home}/archived_sessions")" = "${workspace}/.codex/archived_sessions"
test -d "${workspace}/.codex/archived_sessions/project-a"

disabled_config_home="${tmp_dir}/disabled-config-home/.codex"
CODEX_CONFIG_SYNC_SOURCE='' \
CODEX_HOME="${disabled_config_home}" \
HOME="${tmp_dir}/disabled-config-home" \
    /usr/local/share/codex/sync-config.sh

test ! -e "${disabled_config_home}"

sync_home="${tmp_dir}/sync-home/.codex"
sync_source="${tmp_dir}/mapped-config.toml"
printf 'model = "host-old"\n' > "${sync_source}"

CODEX_CONFIG_SYNC_SOURCE="${sync_source}" \
CODEX_HOME="${sync_home}" \
HOME="${tmp_dir}/sync-home" \
    /usr/local/share/codex/sync-config.sh

test "$(cat "${sync_home}/config.toml")" = 'model = "host-old"'

printf 'model = "local-new"\n' > "${sync_home}/config.toml"
sleep 3
test "$(cat "${sync_source}")" = 'model = "local-new"'

printf 'model = "host-new"\n' > "${sync_source}"
sleep 3
test "$(cat "${sync_home}/config.toml")" = 'model = "host-new"'

kill "$(cat "${sync_home}/.config-sync.pid")"
