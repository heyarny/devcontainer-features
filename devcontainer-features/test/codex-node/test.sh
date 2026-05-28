#!/usr/bin/env bash
set -euo pipefail

node --version
npm --version
codex --version
test -x /usr/local/bin/node
test -x /usr/local/bin/npm
test -x /usr/local/share/codex-node/link-folders.sh

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

workspace="${tmp_dir}/workspace"
codex_home="${tmp_dir}/home/.codex"

mkdir -p "${workspace}/.codex/sessions/project-a"
mkdir -p "${tmp_dir}/home"

CODEX_HOME="${codex_home}" \
HOME="${tmp_dir}/home" \
    /usr/local/share/codex-node/link-folders.sh

test ! -e "${codex_home}"

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

disabled_home="${tmp_dir}/disabled-home/.codex"
CODEX_LINK_FOLDERS='' \
CODEX_HOME="${disabled_home}" \
HOME="${tmp_dir}/disabled-home" \
    /usr/local/share/codex-node/link-folders.sh

test ! -e "${disabled_home}"

absolute_home="${tmp_dir}/absolute-home/.codex"
test ! -e "${workspace}/state/sessions"
CODEX_LINK_FOLDERS="sessions=${workspace}/state/sessions" \
CODEX_HOME="${absolute_home}" \
HOME="${tmp_dir}/absolute-home" \
    /usr/local/share/codex-node/link-folders.sh

test -d "${workspace}/state/sessions"
test "$(readlink "${absolute_home}/sessions")" = "${workspace}/state/sessions"

relative_home="${tmp_dir}/relative-home/.codex"
if CODEX_LINK_FOLDERS='sessions=.codex/sessions' \
    CODEX_HOME="${relative_home}" \
    HOME="${tmp_dir}/relative-home" \
    /usr/local/share/codex-node/link-folders.sh; then
    echo "Expected relative Codex link target to fail." >&2
    exit 1
fi
