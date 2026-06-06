#!/usr/bin/env sh
set -eu

codex --version
test -x /usr/local/bin/codex
test -L /usr/local/bin/codex
test -d /usr/local/share/codex/packages/standalone
test -x /usr/local/share/codex/link-folders.sh

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
