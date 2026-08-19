#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/usr/local/share/codex"
# Preserve a non-empty runtime override before loading the persisted feature option.
codex_link_folders_from_env="${CODEX_LINK_FOLDERS-}"

if [ -f "${INSTALL_DIR}/options.env" ]; then
    # shellcheck disable=SC1091
    . "${INSTALL_DIR}/options.env"
fi

if [ -n "${codex_link_folders_from_env}" ]; then
    link_folders="${codex_link_folders_from_env}"
else
    link_folders="${CODEX_LINK_FOLDERS-}"
fi

codex_home="${CODEX_HOME:-${HOME}/.codex}"

ensure_codex_home_writable() {
    local owner owner_group

    # Never replace CODEX_HOME itself when it is a symlink; only accept a writable target.
    if [ -L "${codex_home}" ]; then
        if [ -d "${codex_home}" ] && [ -w "${codex_home}" ]; then
            return
        fi

        echo "Codex home '${codex_home}' is a symlink but is not writable." >&2
        exit 1
    fi

    if [ -e "${codex_home}" ] && [ ! -d "${codex_home}" ]; then
        echo "Codex home '${codex_home}' exists but is not a directory." >&2
        exit 1
    fi

    if [ ! -e "${codex_home}" ]; then
        mkdir -p "${codex_home}" 2>/dev/null || true
    fi

    if [ -d "${codex_home}" ] && [ -w "${codex_home}" ]; then
        return
    fi

    # Limit privileged ownership repair to the normal ~/.codex tree, never an arbitrary override.
    case "${codex_home}" in
        "${HOME}/.codex"|${HOME}/.codex/*)
            ;;
        *)
            echo "Codex home '${codex_home}' is not writable. Set CODEX_HOME to a writable path or fix its ownership." >&2
            exit 1
            ;;
    esac

    # Non-interactive sudo avoids hanging container startup on a password prompt.
    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
        owner="$(id -un)"
        owner_group="$(id -gn)"
        sudo mkdir -p "${codex_home}"
        sudo chown "${owner}:${owner_group}" "${codex_home}"
    fi

    if [ ! -d "${codex_home}" ] || [ ! -w "${codex_home}" ]; then
        echo "Codex home '${codex_home}' is not writable. Could not repair ownership." >&2
        exit 1
    fi
}

if [ -z "${link_folders}" ]; then
    # Do not create CODEX_HOME just for a disabled hook, but repair it when it already exists.
    if [ -e "${codex_home}" ]; then
        ensure_codex_home_writable
    fi

    exit 0
fi

validate_target() {
    local target="$1"

    # Relative targets would depend on the entrypoint's unspecified working directory.
    if [[ "${target}" != /* ]]; then
        echo "Invalid Codex linked folder target: '${target}'. Use an absolute path." >&2
        exit 1
    fi
}

validate_link_name() {
    local name="$1"

    # Link names become paths below CODEX_HOME, so reject absolute and traversal forms.
    if [ -z "${name}" ] || [[ "${name}" = /* ]] || [[ "${name}" == "." ]] || [[ "${name}" == ".." ]] || [[ "${name}" == *"/.."* ]] || [[ "${name}" == *"../"* ]]; then
        echo "Invalid Codex linked folder name: '${name}'" >&2
        exit 1
    fi
}

link_codex_folder() {
    local name="$1"
    local target="$2"
    local link="${codex_home}/${name}"

    # Validate again at the mutation boundary in case this helper gains another caller.
    validate_link_name "${name}"
    mkdir -p "${target}" "$(dirname "${link}")"

    # Leave an already-correct link untouched to keep repeated starts idempotent.
    if [ -L "${link}" ] && [ "$(readlink "${link}")" = "${target}" ]; then
        return
    fi

    # Replace stale links or empty directories, but never discard non-empty user data.
    if [ -L "${link}" ]; then
        rm "${link}"
    elif [ -e "${link}" ]; then
        rmdir "${link}" 2>/dev/null || {
            echo "Refusing to replace non-empty ${link}; move its contents into ${target} first." >&2
            exit 1
        }
    fi

    ln -s "${target}" "${link}"
}

mirror_session_dirs() {
    local sessions_target="$1"
    local archived_target="$2"

    if [ -z "${sessions_target}" ] || [ -z "${archived_target}" ] || [ ! -d "${sessions_target}" ]; then
        return
    fi

    # Recreate only the directory layout so nested archived-session destinations exist.
    while IFS= read -r -d '' dir; do
        mkdir -p "${archived_target}${dir#"${sessions_target}"}"
    done < <(find "${sessions_target}" -type d -print0)
}

session_target=""
archived_session_target=""

ensure_codex_home_writable

parse_link_folders() {
    local raw_entry entry name raw_target target

    # Commas separate mappings; the first '=' separates a name from its full target.
    IFS=',' read -r -a entries <<< "${link_folders}"

    for raw_entry in "${entries[@]}"; do
        # Ignore whitespace around a mapping without changing spaces inside its path.
        entry="${raw_entry#"${raw_entry%%[![:space:]]*}"}"
        entry="${entry%"${entry##*[![:space:]]}"}"

        if [ -z "${entry}" ]; then
            continue
        fi

        if [[ "${entry}" != *"="* ]]; then
            echo "Invalid Codex linked folder mapping: '${entry}'. Use name=target." >&2
            exit 1
        fi

        name="${entry%%=*}"
        raw_target="${entry#*=}"
        validate_link_name "${name}"
        validate_target "${raw_target}"
        target="${raw_target}"

        # Remember the conventional session targets for the final directory-tree mirror.
        case "${name}" in
            sessions)
                session_target="${target}"
                ;;
            archived_sessions)
                archived_session_target="${target}"
                ;;
        esac

        link_codex_folder "${name}" "${target}"
    done
}

parse_link_folders

mirror_session_dirs "${session_target}" "${archived_session_target}"
