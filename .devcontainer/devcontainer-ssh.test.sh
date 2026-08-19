#!/usr/bin/env bash

set -euo pipefail

if [[ "${DEVCONTAINER_SSH_TEST_DOCKER_STUB:-}" == 1 ]]; then
    printf '%s\n' "$*" >>"${DEVCONTAINER_SSH_TEST_DOCKER_LOG:?}"
    if [[ "${1:-}" == ps && "${DEVCONTAINER_SSH_TEST_CONTAINER_RUNNING:-1}" == 1 ]]; then
        printf '%s\n' test-container-id
    fi
    exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Skipping Dev Container SSH host-helper test: macOS only."
    exit 0
fi

readonly SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly HELPER="${SCRIPT_DIR}/devcontainer-ssh.sh"
readonly TEST_ROOT="$(mktemp -d -t devcontainer-ssh-test.XXXXXX)"
readonly TEST_HOME="${TEST_ROOT}/home"
readonly TEST_WORKSPACE="${TEST_ROOT}/workspace's 100%ready"
readonly TEST_HOSTNAME="Test's 100% Host"
readonly TEST_BIN="${TEST_ROOT}/bin"
readonly DOCKER_LOG="${TEST_ROOT}/docker.log"
readonly ORIGINAL_HOST_CONFIG="${TEST_ROOT}/original-host.conf"
readonly SYMLINK_HOME="${TEST_ROOT}/symlink-home"
readonly SYMLINK_CONFIG_DIR="${TEST_ROOT}/dotfiles/.ssh"
readonly SYMLINK_CONFIG="${SYMLINK_CONFIG_DIR}/config"

cleanup() {
    rm -rf -- "${TEST_ROOT}"
}
trap cleanup EXIT

mkdir -p "${TEST_HOME}/.ssh" "${TEST_WORKSPACE}" "${TEST_BIN}" \
    "${SYMLINK_HOME}/.ssh" "${SYMLINK_CONFIG_DIR}"

printf 'Host regular.example\n    User regular\n' >"${TEST_HOME}/.ssh/config"
printf 'Host existing.example\n    User existing\n' >"${SYMLINK_CONFIG}"
ln -s '../../dotfiles/.ssh/config' "${SYMLINK_HOME}/.ssh/config"

HOME="${SYMLINK_HOME}" "${HELPER}" register \
    --workspace-folder "${TEST_WORKSPACE}" \
    --hostname 'Symlink Config' \
    --remote-user vscode
HOME="${SYMLINK_HOME}" "${HELPER}" register \
    --workspace-folder "${TEST_WORKSPACE}" \
    --hostname 'Symlink Config' \
    --remote-user vscode

test -L "${SYMLINK_HOME}/.ssh/config"
test "$(readlink "${SYMLINK_HOME}/.ssh/config")" = '../../dotfiles/.ssh/config'
test "$(grep -Fxc 'Include ~/.ssh/devcontainers/*.conf' "${SYMLINK_CONFIG}")" -eq 1
grep -Fqx 'Host existing.example' "${SYMLINK_CONFIG}"
grep -Fqx '    User existing' "${SYMLINK_CONFIG}"
test "$(stat -f '%Lp' "${SYMLINK_CONFIG}")" = 600

HOME="${TEST_HOME}" "${HELPER}" register \
    --workspace-folder "${TEST_WORKSPACE}" \
    --hostname "${TEST_HOSTNAME}" \
    --remote-user vscode

test ! -L "${TEST_HOME}/.ssh/config"
test "$(grep -Fxc 'Include ~/.ssh/devcontainers/*.conf' "${TEST_HOME}/.ssh/config")" -eq 1
grep -Fqx 'Host regular.example' "${TEST_HOME}/.ssh/config"
grep -Fqx '    User regular' "${TEST_HOME}/.ssh/config"
test "$(stat -f '%Lp' "${TEST_HOME}/.ssh/config")" = 600

readonly SSH_HOST="$(HOME="${TEST_HOME}" "${HELPER}" resolve --hostname "${TEST_HOSTNAME}")"
readonly HOST_CONFIG="${TEST_HOME}/.ssh/devcontainers/${SSH_HOST}.conf"
readonly CANONICAL_WORKSPACE="$(CDPATH= cd -- "${TEST_WORKSPACE}" && pwd -P)"
proxy_command="$(sed -n 's/^    ProxyCommand //p' "${HOST_CONFIG}")"

if [[ "${proxy_command}" != *"100%%ready"* || "${proxy_command}" != *"100%% Host"* ]]; then
    echo "ProxyCommand did not escape literal percent signs for OpenSSH." >&2
    exit 1
fi

# Decode OpenSSH's literal-percent representation, then verify that the shell
# sees the original values as single arguments.
proxy_command="${proxy_command//%%/%}"
eval "set -- ${proxy_command}"

test "$#" -eq 9
test "$1" = /bin/bash
test "$2" = "${HELPER}"
test "$3" = proxy
test "$4" = --workspace-folder
test "$5" = "${CANONICAL_WORKSPACE}"
test "$6" = --hostname
test "$7" = "${TEST_HOSTNAME}"
test "$8" = --remote-user
test "$9" = vscode

# Let the generated ProxyCommand reach the helper without requiring a real
# container. The test script doubles as docker when invoked through this link.
export DEVCONTAINER_SSH_TEST_DOCKER_LOG="${DOCKER_LOG}"
export DEVCONTAINER_SSH_TEST_DOCKER_STUB=1
ln -s "${SCRIPT_DIR}/devcontainer-ssh.test.sh" "${TEST_BIN}/docker"

set +e
ssh_output="$(PATH="${TEST_BIN}:${PATH}" HOME="${TEST_HOME}" ssh \
    -F "${TEST_HOME}/.ssh/config" \
    -T "${SSH_HOST}" true 2>&1)"
ssh_status=$?
set -e

if [[ "${ssh_output}" == *percent_expand* ]]; then
    echo "OpenSSH rejected the generated ProxyCommand percent escaping." >&2
    exit 1
fi
test "${ssh_status}" -ne 0
grep -Fq "label=devcontainer.local_folder=${CANONICAL_WORKSPACE}" "${DOCKER_LOG}"

# A running container needs Docker only; devcontainer is required solely for startup.
restricted_path="${TEST_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"
if PATH="${restricted_path}" command -v devcontainer >/dev/null 2>&1; then
    echo "Restricted test PATH unexpectedly contains devcontainer." >&2
    exit 1
fi
: >"${DOCKER_LOG}"
PATH="${restricted_path}" HOME="${TEST_HOME}" "${HELPER}" proxy \
    --workspace-folder "${TEST_WORKSPACE}" \
    --hostname "${TEST_HOSTNAME}" \
    --remote-user vscode
grep -Fqx "ps --quiet --filter label=devcontainer.local_folder=${CANONICAL_WORKSPACE}" "${DOCKER_LOG}"
grep -Fqx 'exec --user root test-container-id test -x /usr/sbin/sshd' "${DOCKER_LOG}"
grep -Fqx 'exec -i --user root test-container-id /usr/sbin/sshd -i' "${DOCKER_LOG}"

set +e
stopped_output="$(DEVCONTAINER_SSH_TEST_CONTAINER_RUNNING=0 \
    PATH="${restricted_path}" HOME="${TEST_HOME}" "${HELPER}" proxy \
    --workspace-folder "${TEST_WORKSPACE}" \
    --hostname "${TEST_HOSTNAME}" \
    --remote-user vscode 2>&1)"
stopped_status=$?
set -e
test "${stopped_status}" -ne 0
if [[ "${stopped_output}" != *'Required command not found: devcontainer'* ]]; then
    echo "Stopped-container path did not report the missing devcontainer CLI." >&2
    exit 1
fi

cp "${HOST_CONFIG}" "${ORIGINAL_HOST_CONFIG}"

set +e
HOME="${TEST_HOME}" "${HELPER}" register \
    --workspace-folder "${TEST_WORKSPACE}" \
    --hostname "${TEST_HOSTNAME}" \
    --remote-user 'bad user' >/dev/null 2>&1
failed_update_status=$?
set -e

test "${failed_update_status}" -ne 0
cmp -s "${HOST_CONFIG}" "${ORIGINAL_HOST_CONFIG}"

readonly INVALID_HOSTNAME="Invalid New Host"
readonly INVALID_SSH_HOST="$(HOME="${TEST_HOME}" "${HELPER}" resolve --hostname "${INVALID_HOSTNAME}")"
readonly INVALID_HOST_CONFIG="${TEST_HOME}/.ssh/devcontainers/${INVALID_SSH_HOST}.conf"

set +e
HOME="${TEST_HOME}" "${HELPER}" register \
    --workspace-folder "${TEST_WORKSPACE}" \
    --hostname "${INVALID_HOSTNAME}" \
    --remote-user 'bad user' >/dev/null 2>&1
failed_first_registration_status=$?
set -e

test "${failed_first_registration_status}" -ne 0
test ! -e "${INVALID_HOST_CONFIG}"

HOME="${TEST_HOME}" "${HELPER}" register \
    --workspace-folder "${TEST_WORKSPACE}" \
    --hostname "${TEST_HOSTNAME}" \
    --remote-user node

grep -Fqx '    User node' "${HOST_CONFIG}"
if cmp -s "${HOST_CONFIG}" "${ORIGINAL_HOST_CONFIG}"; then
    echo "Successful registration did not replace the prior host configuration." >&2
    exit 1
fi
test "$(stat -f '%Lp' "${HOST_CONFIG}")" = 600

echo "Dev Container SSH host-helper test passed."
