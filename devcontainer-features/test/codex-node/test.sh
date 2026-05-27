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

WORKSPACE_FOLDER="${workspace}" \
CODEX_HOME="${codex_home}" \
HOME="${tmp_dir}/home" \
    /usr/local/share/codex-node/link-folders.sh

test ! -e "${codex_home}"

csv_home="${tmp_dir}/csv-home/.codex"
CODEX_LINK_FOLDERS='sessions=.codex/sessions,archived_sessions=.codex/archived_sessions' \
WORKSPACE_FOLDER="${workspace}" \
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
        CODEX_LINK_FOLDERS='sessions=.codex/sessions' \
        WORKSPACE_FOLDER="${workspace}" \
        CODEX_HOME="${root_owned_codex_home}" \
        HOME="${root_owned_home}" \
        /usr/local/share/codex-node/link-folders.sh

    test -L "${root_owned_codex_home}/sessions"
    test "$(readlink "${root_owned_codex_home}/sessions")" = "${workspace}/.codex/sessions"
    test "$(stat -c '%U' "${root_owned_codex_home}")" = "vscode"
fi

disabled_home="${tmp_dir}/disabled-home/.codex"
CODEX_LINK_FOLDERS='' \
WORKSPACE_FOLDER="${workspace}" \
CODEX_HOME="${disabled_home}" \
HOME="${tmp_dir}/disabled-home" \
    /usr/local/share/codex-node/link-folders.sh

test ! -e "${disabled_home}"

placeholder_home="${tmp_dir}/placeholder-home/.codex"
CODEX_LINK_FOLDERS='sessions={workspace}/state/sessions' \
WORKSPACE_FOLDER="${workspace}" \
CODEX_HOME="${placeholder_home}" \
HOME="${tmp_dir}/placeholder-home" \
    /usr/local/share/codex-node/link-folders.sh

test "$(readlink "${placeholder_home}/sessions")" = "${workspace}/state/sessions"
