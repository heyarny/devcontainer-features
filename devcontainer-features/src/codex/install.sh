#!/usr/bin/env sh
set -eu

FEATURE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
INSTALLER="${FEATURE_DIR}/install-codex-standalone.sh"

codex_version="${CODEXVERSION-${VERSION:-latest}}"
install_dir="${CODEXINSTALLDIR:-/usr/local/bin}"
standalone_home="${CODEXSTANDALONEHOME:-/usr/local/share/codex}"
codex_link_folders="${CODEXLINKFOLDERS-}"

if [ -z "${codex_version}" ]; then
    codex_version="latest"
fi

case "${codex_version}" in
    latest|rust-v[0-9A-Za-z._~+-]*|[0-9A-Za-z._~+-]*)
        ;;
    *)
        echo "Unsupported Codex version '${codex_version}'. Use 'latest' or a Codex release version." >&2
        exit 1
        ;;
esac

if [ "${install_dir#/}" = "${install_dir}" ] || [ "${standalone_home#/}" = "${standalone_home}" ]; then
    echo "CODEXINSTALLDIR and CODEXSTANDALONEHOME must be absolute paths." >&2
    exit 1
fi

install_prerequisites() {
    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -y --no-install-recommends bash ca-certificates curl tar gzip gawk
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache bash ca-certificates curl tar gzip gawk
    else
        echo "Automatic Codex installation currently supports apt-get or apk base images." >&2
        exit 1
    fi
}

install_prerequisites

mkdir -p "${install_dir}" "${standalone_home}"

CODEX_NON_INTERACTIVE=true \
CODEX_RELEASE="${codex_version}" \
CODEX_INSTALL_DIR="${install_dir}" \
CODEX_HOME="${standalone_home}" \
    sh "${INSTALLER}"

chmod -R a+rX "${standalone_home}"
chmod 0755 "${install_dir}/codex"

{
    printf 'CODEX_LINK_FOLDERS=%s\n' "$(printf '%s' "${codex_link_folders}" | sed "s/'/'\\\\''/g; s/^/'/; s/$/'/")"
} > "${standalone_home}/options.env"

install -m 0755 "${FEATURE_DIR}/link-folders.sh" "${standalone_home}/link-folders.sh"

hash -r 2>/dev/null || true
"${install_dir}/codex" --version
