#!/usr/bin/env bash

set -euo pipefail

if [[ "$(uname -s 2>/dev/null || true)" != "Darwin" ]]; then
    echo "Skipping Dev Container SSH registration: this helper currently supports macOS hosts only." >&2
    exit 0
fi

readonly SSH_SUFFIX=".devcontainer"
readonly SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly DEFAULT_WORKSPACE="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd -P)"
readonly SSH_ROOT="${HOME}/.ssh"
readonly MANAGED_DIR="${SSH_ROOT}/devcontainers"
readonly SSH_CONFIG="${SSH_ROOT}/config"
readonly INCLUDE_LINE="Include ~/.ssh/devcontainers/*.conf"

usage() {
    cat >&2 <<'EOF'
Usage: .devcontainer/devcontainer-ssh.sh <command> [options]

Commands:
  register    Create or update a portless SSH alias.
  proxy       Start/find the dev container and relay SSH over docker exec.
  resolve     Print the normalized SSH host without changing anything.
  status      Show the derived SSH alias and matching running container.
  unregister  Remove the derived SSH alias.

Options:
  --workspace-folder <path>  Local workspace (defaults to the repository root).
  --hostname <name>          Name to normalize into the generated SSH host.
  --remote-user <user>       Dev Container user used for SSH.

The hostname is normalized and receives the suffix ".devcontainer".
The --hostname and --remote-user options are required by register and proxy.
EOF
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Required command not found: $1" >&2
        exit 1
    fi
}

require_value() {
    local value="$1"
    local label="$2"
    if [[ -z "${value}" ]]; then
        echo "Missing required ${label}." >&2
        usage
        exit 2
    fi
}

canonical_workspace() {
    local workspace="${1:-${DEFAULT_WORKSPACE}}"

    if [[ ! -d "${workspace}" ]]; then
        echo "Workspace does not exist: ${workspace}" >&2
        exit 1
    fi

    CDPATH= cd -- "${workspace}" && pwd -P
}

normalize_name() {
    local name="$1"
    local normalized

    normalized="$(printf '%s' "${name}" \
        | LC_ALL=C tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g' \
        | cut -c 1-63 \
        | sed -E 's/-+$//')"
    if [[ -z "${normalized}" ]]; then
        echo "The hostname cannot be normalized into an SSH host." >&2
        exit 1
    fi
    printf '%s%s\n' "${normalized}" "${SSH_SUFFIX}"
}

shell_quote() {
    local value="$1"
    local quoted="'"

    while [[ "${value}" == *"'"* ]]; do
        quoted+="${value%%\'*}'\\''"
        value="${value#*\'}"
    done
    quoted+="${value}'"
    printf '%s' "${quoted}"
}

resolve_symlink_target() {
    local path="$1"
    local link_target
    local target_dir
    local target_name
    local hop_count=0

    while [[ -L "${path}" ]]; do
        if (( hop_count >= 40 )); then
            return 1
        fi
        if ! link_target="$(readlink "${path}")"; then
            return 1
        fi
        if [[ "${link_target}" == /* ]]; then
            path="${link_target}"
        else
            path="$(dirname -- "${path}")/${link_target}"
        fi
        hop_count=$((hop_count + 1))
    done

    target_dir="$(dirname -- "${path}")"
    target_name="$(basename -- "${path}")"
    if ! target_dir="$(CDPATH= cd -- "${target_dir}" 2>/dev/null && pwd -P)"; then
        return 1
    fi
    printf '%s/%s\n' "${target_dir}" "${target_name}"
}

ensure_include() {
    local config_path="${SSH_CONFIG}"
    local config_dir
    local config_name
    local temp_config

    mkdir -p "${MANAGED_DIR}"
    chmod 700 "${SSH_ROOT}" "${MANAGED_DIR}"

    if [[ -L "${SSH_CONFIG}" ]]; then
        if ! config_path="$(resolve_symlink_target "${SSH_CONFIG}")"; then
            echo "Cannot safely resolve SSH config symlink: ${SSH_CONFIG}" >&2
            return 1
        fi
    fi
    if [[ -e "${config_path}" && ! -f "${config_path}" ]]; then
        echo "SSH config is not a regular file: ${config_path}" >&2
        return 1
    fi

    config_dir="$(dirname -- "${config_path}")"
    config_name="$(basename -- "${config_path}")"

    if ! grep -Fqx "${INCLUDE_LINE}" "${config_path}" 2>/dev/null; then
        # Replace the resolved target in its own directory so a config symlink stays intact.
        temp_config="$(mktemp "${config_dir}/.${config_name}.XXXXXX")"
        {
            printf '%s\n\n' "${INCLUDE_LINE}"
            if [[ -e "${config_path}" ]]; then
                cat "${config_path}"
            fi
        } >"${temp_config}"
        chmod 600 "${temp_config}"
        mv "${temp_config}" "${config_path}"
    else
        chmod 600 "${config_path}"
    fi
}

running_container_ids() {
    local workspace="$1"

    docker ps --quiet \
        --filter "label=devcontainer.local_folder=${workspace}" \
        </dev/null
}

select_running_container() {
    local workspace="$1"
    local container_ids

    container_ids="$(running_container_ids "${workspace}")"
    if [[ -z "${container_ids}" ]]; then
        return 1
    fi
    if [[ "${container_ids}" == *$'\n'* ]]; then
        echo "Multiple running Dev Containers match ${workspace}:" >&2
        printf '%s\n' "${container_ids}" >&2
        return 2
    fi

    printf '%s\n' "${container_ids}"
}

start_container() {
    local workspace="$1"
    local log_file

    require_command devcontainer
    log_file="$(mktemp -t devcontainer-ssh-up.XXXXXX)"
    if ! devcontainer up \
        --workspace-folder "${workspace}" \
        --log-format json >"${log_file}" 2>&1; then
        cat "${log_file}" >&2
        rm -f "${log_file}"
        exit 1
    fi
    rm -f "${log_file}"
}

register_host() {
    local workspace="$1"
    local declared_hostname="$2"
    local remote_user="$3"
    local ssh_host
    local host_config
    local candidate_config
    local proxy_command

    require_command ssh
    require_value "${declared_hostname}" hostname
    require_value "${remote_user}" remote-user

    workspace="$(canonical_workspace "${workspace}")"
    ssh_host="$(normalize_name "${declared_hostname}")"
    host_config="${MANAGED_DIR}/${ssh_host}.conf"
    ensure_include

    proxy_command="/bin/bash $(shell_quote "${SCRIPT_DIR}/devcontainer-ssh.sh") proxy --workspace-folder $(shell_quote "${workspace}") --hostname $(shell_quote "${declared_hostname}") --remote-user $(shell_quote "${remote_user}")"
    proxy_command="${proxy_command//%/%%}"
    candidate_config="$(mktemp "${MANAGED_DIR}/.${ssh_host}.XXXXXX")"
    cat >"${candidate_config}" <<EOF
Host ${ssh_host}
    HostName ${ssh_host}
    User ${remote_user}
    BatchMode yes
    PubkeyAuthentication no
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    ProxyCommand ${proxy_command}
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
    ServerAliveInterval 15
    ServerAliveCountMax 3
EOF
    chmod 600 "${candidate_config}"

    if ! ssh -G -T -F "${candidate_config}" "${ssh_host}" >/dev/null 2>&1; then
        rm -f "${candidate_config}"
        echo "Generated SSH configuration is invalid for '${ssh_host}'." >&2
        return 1
    fi

    if ! mv "${candidate_config}" "${host_config}"; then
        rm -f "${candidate_config}"
        return 1
    fi
    echo "Registered portless SSH host '${ssh_host}' for ${workspace}."
}

proxy_connection() {
    local workspace="$1"
    local declared_hostname="$2"
    local remote_user="$3"
    local container_id
    local select_status

    require_command docker
    require_value "${declared_hostname}" hostname
    require_value "${remote_user}" remote-user

    workspace="$(canonical_workspace "${workspace}")"

    if container_id="$(select_running_container "${workspace}")"; then
        :
    else
        select_status=$?
        if [[ "${select_status}" -ne 1 ]]; then
            exit "${select_status}"
        fi
        start_container "${workspace}"
        if ! container_id="$(select_running_container "${workspace}")"; then
            echo "Could not find the running '${declared_hostname}' Dev Container after startup." >&2
            exit 1
        fi
    fi

    if ! docker exec --user root "${container_id}" test -x /usr/sbin/sshd </dev/null; then
        echo "The '${declared_hostname}' Dev Container does not provide /usr/sbin/sshd." >&2
        exit 1
    fi

    exec docker exec -i --user root "${container_id}" /usr/sbin/sshd -i
}

show_status() {
    local workspace="$1"
    local declared_hostname="$2"
    local ssh_host
    local host_config
    local container_id
    local select_status

    require_command docker
    require_value "${declared_hostname}" hostname

    workspace="$(canonical_workspace "${workspace}")"
    ssh_host="$(normalize_name "${declared_hostname}")"
    host_config="${MANAGED_DIR}/${ssh_host}.conf"

    echo "SSH host: ${ssh_host}"
    if [[ -f "${host_config}" ]]; then
        echo "Registration: present"
    else
        echo "Registration: missing"
    fi
    if container_id="$(select_running_container "${workspace}")"; then
        echo "Container: running (${container_id:0:12})"
    else
        select_status=$?
        if [[ "${select_status}" -eq 1 ]]; then
            echo "Container: stopped or missing"
        else
            exit "${select_status}"
        fi
    fi
}

unregister_host() {
    local declared_hostname="$1"
    local ssh_host

    require_value "${declared_hostname}" hostname
    ssh_host="$(normalize_name "${declared_hostname}")"

    rm -f \
        "${MANAGED_DIR}/${ssh_host}.conf" \
        "${MANAGED_DIR}/${ssh_host}" \
        "${MANAGED_DIR}/${ssh_host}.pub"
    echo "Removed SSH host '${ssh_host}'."
}

resolve_host() {
    local declared_hostname="$1"

    require_value "${declared_hostname}" hostname
    normalize_name "${declared_hostname}"
}

command="${1:-}"
if [[ -z "${command}" ]]; then
    usage
    exit 2
fi
shift

workspace="${DEFAULT_WORKSPACE}"
declared_hostname=""
remote_user=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace-folder)
            require_value "${2:-}" workspace-folder
            workspace="$2"
            shift 2
            ;;
        --config)
            # Older generated entries included this selector. Container lookup
            # now intentionally relies only on the workspace label.
            require_value "${2:-}" config
            shift 2
            ;;
        --hostname)
            require_value "${2:-}" hostname
            declared_hostname="$2"
            shift 2
            ;;
        --remote-user)
            require_value "${2:-}" remote-user
            remote_user="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 2
            ;;
    esac
done

case "${command}" in
    register)
        register_host "${workspace}" "${declared_hostname}" "${remote_user}"
        ;;
    proxy)
        proxy_connection "${workspace}" "${declared_hostname}" "${remote_user}"
        ;;
    resolve)
        resolve_host "${declared_hostname}"
        ;;
    status)
        show_status "${workspace}" "${declared_hostname}"
        ;;
    unregister)
        unregister_host "${declared_hostname}"
        ;;
    *)
        usage
        exit 2
        ;;
esac
