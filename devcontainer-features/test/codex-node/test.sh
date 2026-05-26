#!/usr/bin/env bash
set -euo pipefail

node --version
npm --version
codex --version
test -x /usr/local/bin/node
test -x /usr/local/bin/npm
test -x /usr/local/share/codex-devcontainer/setup-links.sh

remote_user="$(id -un)"
remote_group="$(id -gn)"
remote_home="$(getent passwd "${remote_user}" | cut -d: -f6)"

test -d "${remote_home}/.codex"
test "$(stat -c '%U:%G' "${remote_home}/.codex")" = "${remote_user}:${remote_group}"
touch "${remote_home}/.codex/install-write-probe"
rm -f "${remote_home}/.codex/install-write-probe"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

workspace="${tmp_dir}/workspace"
codex_home="${tmp_dir}/home/.codex"

mkdir -p "${workspace}/.codex/sessions/project-a"
mkdir -p "${tmp_dir}/home"

WORKSPACE_FOLDER="${workspace}" \
CODEX_HOME="${codex_home}" \
HOME="${tmp_dir}/home" \
    /usr/local/share/codex-devcontainer/setup-links.sh

test ! -e "${codex_home}"

csv_home="${tmp_dir}/csv-home/.codex"
CODEX_LINKED_FOLDERS='sessions=.codex/sessions,archived_sessions=.codex/archived_sessions' \
WORKSPACE_FOLDER="${workspace}" \
CODEX_HOME="${csv_home}" \
HOME="${tmp_dir}/csv-home" \
    /usr/local/share/codex-devcontainer/setup-links.sh

test -L "${csv_home}/sessions"
test -L "${csv_home}/archived_sessions"
test "$(readlink "${csv_home}/sessions")" = "${workspace}/.codex/sessions"
test "$(readlink "${csv_home}/archived_sessions")" = "${workspace}/.codex/archived_sessions"
test -d "${workspace}/.codex/archived_sessions/project-a"

unwritable_home="${tmp_dir}/unwritable-home/.codex"
mkdir -p "${unwritable_home}"
chmod u-w "${unwritable_home}"
CODEX_LINKED_FOLDERS='sessions=.codex/sessions' \
WORKSPACE_FOLDER="${workspace}" \
CODEX_HOME="${unwritable_home}" \
HOME="${tmp_dir}/unwritable-home" \
    /usr/local/share/codex-devcontainer/setup-links.sh

test -L "${unwritable_home}/sessions"
test "$(readlink "${unwritable_home}/sessions")" = "${workspace}/.codex/sessions"

disabled_home="${tmp_dir}/disabled-home/.codex"
CODEX_LINKED_FOLDERS='' \
WORKSPACE_FOLDER="${workspace}" \
CODEX_HOME="${disabled_home}" \
HOME="${tmp_dir}/disabled-home" \
    /usr/local/share/codex-devcontainer/setup-links.sh

test ! -e "${disabled_home}"

json_home="${tmp_dir}/json-home/.codex"
CODEX_LINKED_FOLDERS='[{"name":"sessions","target":"{workspace}/state/sessions"}]' \
WORKSPACE_FOLDER="${workspace}" \
CODEX_HOME="${json_home}" \
HOME="${tmp_dir}/json-home" \
    /usr/local/share/codex-devcontainer/setup-links.sh

test "$(readlink "${json_home}/sessions")" = "${workspace}/state/sessions"

object_home="${tmp_dir}/object-home/.codex"
CODEX_LINKED_FOLDERS='{"sessions":".codex/custom-sessions"}' \
WORKSPACE_FOLDER="${workspace}" \
CODEX_HOME="${object_home}" \
HOME="${tmp_dir}/object-home" \
    /usr/local/share/codex-devcontainer/setup-links.sh

test "$(readlink "${object_home}/sessions")" = "${workspace}/.codex/custom-sessions"
