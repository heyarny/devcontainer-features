#!/usr/bin/env sh
set -eu

codex --version
test -x /usr/local/share/codex/link-folders.sh

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}" /tmp/codex-sessions /tmp/codex-archived-sessions' EXIT

codex_home="${tmp_dir}/home/.codex"
mkdir -p "${tmp_dir}/home" /tmp/codex-sessions/project-a

CODEX_HOME="${codex_home}" \
HOME="${tmp_dir}/home" \
    /usr/local/share/codex/link-folders.sh

test -L "${codex_home}/sessions"
test -L "${codex_home}/archived_sessions"
test "$(readlink "${codex_home}/sessions")" = "/tmp/codex-sessions"
test "$(readlink "${codex_home}/archived_sessions")" = "/tmp/codex-archived-sessions"
test -d "/tmp/codex-archived-sessions/project-a"
