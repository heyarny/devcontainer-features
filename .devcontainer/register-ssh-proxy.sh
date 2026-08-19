#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

exec "${SCRIPT_DIR}/devcontainer-ssh.sh" register \
    --workspace-folder "${SCRIPT_DIR}/.." \
    --hostname devcontainer-features \
    --remote-user vscode
