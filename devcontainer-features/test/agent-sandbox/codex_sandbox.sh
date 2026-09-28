#!/bin/sh
set -eu

if [ "$(id -u)" -eq 0 ]; then
    exec runuser -u vscode -- "$0"
fi

test "$(codex --version)" = 'codex-cli 0.158.0'

probe="/home/vscode/.codex-sandbox-probe-$$"
printf 'original' > "${probe}"
trap 'rm -f "${probe}"' EXIT

codex sandbox /bin/sh -c 'test -r /etc/os-release'

if codex sandbox /bin/sh -c 'printf changed > "$1"' sh "${probe}"; then
    echo "Codex sandbox allowed a write outside the workspace." >&2
    exit 1
fi

test "$(cat "${probe}")" = 'original'
