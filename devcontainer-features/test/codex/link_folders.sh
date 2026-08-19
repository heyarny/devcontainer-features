#!/usr/bin/env sh
set -eu

# Default-options contract: Codex and the folder-link helper are installed.
codex --version
test -x /usr/local/share/codex/link-folders.sh

# The feature defaults point outside the temporary home, so cleanup covers both
# the home and the configured session targets.
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}" /tmp/codex-sessions /tmp/codex-archived-sessions' EXIT

# Linking creates both configured symlinks and mirrors an existing session
# directory into the archived-session target.
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
