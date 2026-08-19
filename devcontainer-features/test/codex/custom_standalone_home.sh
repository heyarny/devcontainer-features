#!/usr/bin/env sh
set -eu

# Custom-install contract: the pinned standalone release and its complete runtime
# are installed below the requested /opt home with feature options persisted.
codex --version | grep -Eq '(^|[[:space:]])0\.146\.1$'
test -x /usr/local/share/codex/install-codex-standalone.sh
test -x /usr/local/share/codex/update.sh
test -x /usr/local/share/codex/version-policy.sh
test -f /usr/local/share/codex/install.env
grep -q "CODEX_FEATURE_STANDALONE_HOME='/opt/codex-standalone'" /usr/local/share/codex/install.env
test -x /usr/local/share/codex/link-folders.sh
test -x /usr/local/share/codex/sync-config.sh
test -f /usr/local/share/codex/options.env
test -d /opt/codex-standalone/packages/standalone
test -x /opt/codex-standalone/packages/standalone/current/bin/codex-code-mode-host

# The fixture maps session storage and the host config to explicit /tmp paths;
# cleanup removes both the test home and those external targets.
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}" /tmp/codex-custom-sessions /tmp/codex-custom-config.toml' EXIT

codex_home="${tmp_dir}/home/.codex"
mkdir -p "${tmp_dir}/home" /tmp/codex-custom-sessions
printf 'model = "host-custom"\n' > /tmp/codex-custom-config.toml

# The folder helper must honor the persisted custom session target.
CODEX_HOME="${codex_home}" \
HOME="${tmp_dir}/home" \
    /usr/local/share/codex/link-folders.sh

test -L "${codex_home}/sessions"
test "$(readlink "${codex_home}/sessions")" = "/tmp/codex-custom-sessions"

# One-shot sync copies the persisted host config without starting a watcher or
# leaving a PID file behind.
CODEX_HOME="${codex_home}" \
HOME="${tmp_dir}/home" \
    /usr/local/share/codex/sync-config.sh --once

test "$(cat "${codex_home}/config.toml")" = 'model = "host-custom"'
test ! -e "${codex_home}/.config-sync.pid"
