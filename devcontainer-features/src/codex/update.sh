#!/usr/bin/env sh
set -eu

SUPPORT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
INSTALLER="${SUPPORT_DIR}/install-codex-standalone.sh"
INSTALL_ENV="${SUPPORT_DIR}/install.env"

if [ -f "${INSTALL_ENV}" ]; then
    # shellcheck disable=SC1090
    . "${INSTALL_ENV}"
fi

CODEX_NON_INTERACTIVE="${CODEX_NON_INTERACTIVE:-true}" \
CODEX_RELEASE="${CODEX_RELEASE:-latest}" \
CODEX_INSTALL_DIR="${CODEX_INSTALL_DIR:-${CODEX_FEATURE_INSTALL_DIR:-/usr/local/bin}}" \
CODEX_HOME="${CODEX_HOME:-${CODEX_FEATURE_STANDALONE_HOME:-/usr/local/share/codex}}" \
    sh "${INSTALLER}" "$@"
