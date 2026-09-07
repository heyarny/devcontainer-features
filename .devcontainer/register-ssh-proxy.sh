#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# Pass --forward-agent to let SSH and Git commands in the container use keys
# from the host SSH agent while the connection is open. Private keys are not
# copied, but trusted container processes can request signatures. Omitting the
# option explicitly disables agent forwarding for the registered alias.
exec "${SCRIPT_DIR}/devcontainer-ssh.sh" register \
    --workspace-folder "${SCRIPT_DIR}/.." \
    --hostname devcontainer-features \
    --remote-user vscode \
    "$@"
