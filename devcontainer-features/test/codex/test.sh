#!/usr/bin/env sh
set -eu

codex --version
test -x /usr/local/bin/codex
test -L /usr/local/bin/codex
test -d /usr/local/share/codex/packages/standalone
test -x /usr/local/share/codex/link-folders.sh
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
