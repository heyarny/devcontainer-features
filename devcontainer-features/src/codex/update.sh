#!/usr/bin/env sh
set -eu

# This installed wrapper reapplies feature policy and saved install paths while
# forwarding the update request unchanged to OpenAI's vendored installer.
SUPPORT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
INSTALLER="${SUPPORT_DIR}/install-codex-standalone.sh"
INSTALL_ENV="${SUPPORT_DIR}/install.env"
VERSION_POLICY="${SUPPORT_DIR}/version-policy.sh"

# Version validation lives in feature-owned code so the upstream file is not edited.
# shellcheck disable=SC1090
. "${VERSION_POLICY}"

# Recover non-default paths chosen when the feature was first installed.
if [ -f "${INSTALL_ENV}" ]; then
    # shellcheck disable=SC1090
    . "${INSTALL_ENV}"
fi

codex_feature_validate_update_request() {
    # Environment selection is the baseline; repeated --release flags follow
    # the upstream installer's last-one-wins behavior.
    codex_feature_update_release="${CODEX_RELEASE:-latest}"

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --release)
                if [ "$#" -lt 2 ]; then
                    # Let the upstream parser produce its canonical missing-value error.
                    return 0
                fi
                codex_feature_update_release="$2"
                shift 2
                ;;
            --help|-h)
                # Help must remain available even if CODEX_RELEASE is outdated.
                return 0
                ;;
            *)
                # Preserve the vendored installer's own argument error and text.
                return 0
                ;;
        esac
    done

    codex_feature_validate_release "${codex_feature_update_release}"
}

codex_feature_validate_update_request "$@"

# Explicit update environment values override persisted feature paths, which in
# turn override defaults. CLI arguments stay last so the upstream parser can
# apply options such as --release exactly as documented.
CODEX_NON_INTERACTIVE="${CODEX_NON_INTERACTIVE:-true}" \
CODEX_RELEASE="${CODEX_RELEASE:-latest}" \
CODEX_INSTALL_DIR="${CODEX_INSTALL_DIR:-${CODEX_FEATURE_INSTALL_DIR:-/usr/local/bin}}" \
CODEX_HOME="${CODEX_HOME:-${CODEX_FEATURE_STANDALONE_HOME:-/usr/local/share/codex}}" \
    sh "${INSTALLER}" "$@"
