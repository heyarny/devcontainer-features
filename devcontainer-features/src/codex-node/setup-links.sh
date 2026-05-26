#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/usr/local/share/codex-devcontainer"

if [ -f "${INSTALL_DIR}/options.env" ]; then
    # shellcheck disable=SC1091
    . "${INSTALL_DIR}/options.env"
fi

linked_folders="${CODEX_LINKED_FOLDERS-${CODEX_LINKED_FOLDERS_FROM_OPTIONS-}}"

if [ -z "${linked_folders}" ]; then
    exit 0
fi

workspace_folder="${WORKSPACE_FOLDER:-${DEVCONTAINER_WORKSPACE_FOLDER:-${PWD:-/workspace}}}"
codex_home="${CODEX_HOME:-${HOME}/.codex}"

run_sudo() {
    if command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        "$@"
    fi
}

ensure_writable_dir() {
    local dir="$1"

    chmod u+rwx "${dir}" 2>/dev/null || true

    if [ -w "${dir}" ]; then
        return
    fi

    run_sudo chown "$(id -u):$(id -g)" "${dir}"
    run_sudo chmod u+rwx "${dir}"
}

ensure_dir() {
    local dir="$1"

    if [ -d "${dir}" ]; then
        if [ ! -w "${dir}" ]; then
            ensure_writable_dir "${dir}"
        fi
        return
    fi

    if ! mkdir -p "${dir}" 2>/dev/null; then
        run_sudo mkdir -p "${dir}"
        ensure_writable_dir "${dir}"
    fi
}

expand_target() {
    local target="$1"

    target="${target//\$\{workspace\}/${workspace_folder}}"
    target="${target//\$workspace/${workspace_folder}}"
    target="${target//\$\{workspaceFolder\}/${workspace_folder}}"
    target="${target//\$workspaceFolder/${workspace_folder}}"
    target="${target//\$\{localWorkspaceFolder\}/${workspace_folder}}"
    target="${target//\{workspace\}/${workspace_folder}}"
    target="${target//\{workspaceFolder\}/${workspace_folder}}"
    target="${target//\{localWorkspaceFolder\}/${workspace_folder}}"
    target="${target/#\~/${HOME}}"

    if [[ "${target}" == /.codex/* ]]; then
        target="${workspace_folder}${target}"
    elif [[ "${target}" != /* ]]; then
        target="${workspace_folder}/${target}"
    fi

    printf '%s\n' "${target}"
}

ensure_safe_link_name() {
    local name="$1"

    if [ -z "${name}" ] || [[ "${name}" = /* ]] || [[ "${name}" == *..* ]]; then
        echo "Invalid Codex linked folder name: '${name}'" >&2
        exit 1
    fi
}

link_folder() {
    local name="$1"
    local target="$2"
    local link="${codex_home}/${name}"

    ensure_safe_link_name "${name}"
    ensure_dir "${target}"
    ensure_dir "$(dirname "${link}")"

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

parse_json_linked_folders() {
    local json="$1"

    if ! command -v node >/dev/null 2>&1; then
        echo "node is required to parse JSON linkedFolders." >&2
        exit 1
    fi

    LINKED_FOLDERS_JSON="${json}" node <<'EOF'
const input = process.env.LINKED_FOLDERS_JSON || '';

function parseRelaxedObjectList(value) {
  const trimmed = value.trim();

  if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) {
    throw new Error('relaxed linkedFolders syntax must be an array');
  }

  const body = trimmed.slice(1, -1).trim();
  if (!body) {
    return [];
  }

  return body
    .replace(/^\{/, '')
    .replace(/\}$/, '')
    .split(/\}\s*,\s*\{/)
    .map((entry) => {
      const object = {};

      for (const part of entry.split(/\s*,\s*/)) {
        const separator = part.indexOf(':');
        if (separator === -1) {
          throw new Error(`invalid relaxed linkedFolders entry: ${part}`);
        }

        const key = part.slice(0, separator).trim().replace(/^['"]|['"]$/g, '');
        const rawValue = part.slice(separator + 1).trim().replace(/^['"]|['"]$/g, '');
        object[key] = rawValue;
      }

      return object;
    });
}

function parseLinkedFolders(value) {
  try {
    return JSON.parse(value);
  } catch (jsonError) {
    try {
      return parseRelaxedObjectList(value);
    } catch (relaxedError) {
      throw new Error(`${jsonError.message}; relaxed parser: ${relaxedError.message}`);
    }
  }
}

let parsed;

try {
  parsed = parseLinkedFolders(input);
} catch (error) {
  console.error(`Invalid linkedFolders JSON: ${error.message}`);
  process.exit(1);
}

const entries = Array.isArray(parsed)
  ? parsed
  : Object.entries(parsed).map(([name, target]) => ({ name, target }));

for (const entry of entries) {
  if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
    console.error('Each linkedFolders JSON entry must be an object.');
    process.exit(1);
  }

  const name = entry.name ?? entry.linkName;
  const target = entry.target ?? entry.path;

  if (typeof name !== 'string' || typeof target !== 'string') {
    console.error('Each linkedFolders JSON entry must include string name and target fields.');
    process.exit(1);
  }

  if (name.includes('\t') || name.includes('\n') || target.includes('\t') || target.includes('\n')) {
    console.error('linkedFolders names and targets may not contain tab or newline characters.');
    process.exit(1);
  }

  console.log(`${name}\t${target}`);
}
EOF
}

ensure_dir "${codex_home}"

session_target=""
archived_session_target=""

handle_mapping() {
    local name="$1"
    local raw_target="$2"
    local target

    ensure_safe_link_name "${name}"
    target="$(expand_target "${raw_target}")"

    case "${name}" in
        sessions)
            session_target="${target}"
            ;;
        archived_sessions)
            archived_session_target="${target}"
            ;;
    esac

    link_folder "${name}" "${target}"
}

parse_legacy_linked_folders() {
    local raw_entry entry name raw_target

    IFS=',' read -r -a entries <<< "${linked_folders}"

    for raw_entry in "${entries[@]}"; do
        entry="${raw_entry#"${raw_entry%%[![:space:]]*}"}"
        entry="${entry%"${entry##*[![:space:]]}"}"

        if [ -z "${entry}" ]; then
            continue
        fi

        if [[ "${entry}" == *"="* ]]; then
            name="${entry%%=*}"
            raw_target="${entry#*=}"
        elif [[ "${entry}" == *":"* ]]; then
            name="${entry%%:*}"
            raw_target="${entry#*:}"
        else
            name="${entry}"
            raw_target=".codex/${entry}"
        fi

        handle_mapping "${name}" "${raw_target}"
    done
}

trimmed_linked_folders="${linked_folders#"${linked_folders%%[![:space:]]*}"}"

if [[ "${trimmed_linked_folders}" == \[* ]] || [[ "${trimmed_linked_folders}" == \{* ]]; then
    while IFS=$'\t' read -r name raw_target; do
        handle_mapping "${name}" "${raw_target}"
    done < <(parse_json_linked_folders "${linked_folders}")
else
    parse_legacy_linked_folders
fi

mirror_session_dirs "${session_target}" "${archived_session_target}"
