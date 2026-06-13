#!/usr/bin/env sh
set -eu

codex --version
test -x /usr/local/share/codex/install-codex-standalone.sh
test -x /usr/local/share/codex/update.sh
test -f /usr/local/share/codex/install.env
grep -q "CODEX_FEATURE_STANDALONE_HOME='/opt/codex-standalone'" /usr/local/share/codex/install.env
test -x /usr/local/share/codex/link-folders.sh
test -x /usr/local/share/codex/sync-config.sh
test -f /usr/local/share/codex/options.env
test -d /opt/codex-standalone/packages/standalone

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}" /tmp/codex-custom-sessions /tmp/codex-custom-config.toml' EXIT

codex_home="${tmp_dir}/home/.codex"
mkdir -p "${tmp_dir}/home" /tmp/codex-custom-sessions
printf 'model = "host-custom"\n' > /tmp/codex-custom-config.toml

CODEX_HOME="${codex_home}" \
HOME="${tmp_dir}/home" \
    /usr/local/share/codex/link-folders.sh

test -L "${codex_home}/sessions"
test "$(readlink "${codex_home}/sessions")" = "/tmp/codex-custom-sessions"

CODEX_HOME="${codex_home}" \
HOME="${tmp_dir}/home" \
    /usr/local/share/codex/sync-config.sh

test "$(cat "${codex_home}/config.toml")" = 'model = "host-custom"'

kill "$(cat "${codex_home}/.config-sync.pid")"
