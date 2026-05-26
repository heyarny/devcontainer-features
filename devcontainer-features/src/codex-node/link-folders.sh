#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/usr/local/share/codex-node"

if [ -f "${INSTALL_DIR}/options.env" ]; then
    # shellcheck disable=SC1091
    . "${INSTALL_DIR}/options.env"
fi

link_folders="${CODEX_LINK_FOLDERS-${CODEX_LINK_FOLDERS_FROM_OPTIONS-}}"

if [ -z "${link_folders}" ]; then
    exit 0
fi

workspace_folder="${WORKSPACE_FOLDER:-${DEVCONTAINER_WORKSPACE_FOLDER:-/workspace}}"
codex_home="${CODEX_HOME:-${HOME}/.codex}"

resolve_target() {
    local target="$1"

    target="${target//\{workspace\}/${workspace_folder}}"
    target="${target//\{workspaceFolder\}/${workspace_folder}}"
    target="${target//\{localWorkspaceFolder\}/${workspace_folder}}"

    if [[ "${target}" == /.codex/* ]]; then
        target="${workspace_folder}${target}"
    elif [[ "${target}" != /* ]]; then
        target="${workspace_folder}/${target}"
    fi

    printf '%s\n' "${target}"
}

validate_link_name() {
    local name="$1"

    if [ -z "${name}" ] || [[ "${name}" = /* ]] || [[ "${name}" == "." ]] || [[ "${name}" == ".." ]] || [[ "${name}" == *"/.."* ]] || [[ "${name}" == *"../"* ]]; then
        echo "Invalid Codex linked folder name: '${name}'" >&2
        exit 1
    fi
}

link_codex_folder() {
    local name="$1"
    local target="$2"
    local link="${codex_home}/${name}"

    validate_link_name "${name}"
    mkdir -p "${target}" "$(dirname "${link}")"

    if [ -L "${link}" ] && [ "$(readlink "${link}")" = "${target}" ]; then
        return
    fi

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

    while IFS= read -r -d '' dir; do
        mkdir -p "${archived_target}${dir#"${sessions_target}"}"
    done < <(find "${sessions_target}" -type d -print0)
}

session_target=""
archived_session_target=""

parse_link_folders() {
    local raw_entry entry name raw_target target

    IFS=',' read -r -a entries <<< "${link_folders}"

    for raw_entry in "${entries[@]}"; do
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
        target="$(resolve_target "${raw_target}")"

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
