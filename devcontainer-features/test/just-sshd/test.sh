#!/bin/sh

set -eu

sudo_if() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

target_user="${_REMOTE_USER:-vscode}"
case "${target_user}" in
    ''|auto|automatic|none|root)
        target_user="vscode"
        ;;
esac

effective_config="$(sudo_if /usr/sbin/sshd -T -C "user=${target_user},host=localhost,addr=127.0.0.1")"

printf '%s\n' "${effective_config}" | grep -Fqx 'listenaddress 127.0.0.1:2222'
printf '%s\n' "${effective_config}" | grep -Fqx 'permitrootlogin no'
printf '%s\n' "${effective_config}" | grep -Fqx 'passwordauthentication yes'
printf '%s\n' "${effective_config}" | grep -Fqx 'permitemptypasswords yes'
printf '%s\n' "${effective_config}" | grep -Fqx 'kbdinteractiveauthentication no'
printf '%s\n' "${effective_config}" | grep -Fqx 'pubkeyauthentication no'
printf '%s\n' "${effective_config}" | grep -Fqx 'usepam no'
printf '%s\n' "${effective_config}" | grep -Eq "^allowusers ${target_user}( |$)"

password_field="$(sudo_if getent shadow "${target_user}" | cut -d: -f2)"
test -z "${password_field}"

if [ "$(id -u)" -eq 0 ]; then
    proxy_command="/usr/sbin/sshd -i"
else
    proxy_command="sudo /usr/sbin/sshd -i"
fi

# Prove the client's initial "none" request succeeds while every
# credential-bearing method is disabled and sshd uses stdio instead of TCP.
attempts=0
while ! ssh -F /dev/null \
    -o BatchMode=yes \
    -o ConnectTimeout=2 \
    -o "ProxyCommand=${proxy_command}" \
    -o PubkeyAuthentication=no \
    -o PasswordAuthentication=no \
    -o KbdInteractiveAuthentication=no \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "${target_user}@just-sshd.test" true >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [ "${attempts}" -ge 10 ]; then
        echo "Timed out waiting for unauthenticated SSH access." >&2
        exit 1
    fi
    sleep 1
done

actual_user="$(ssh -F /dev/null \
    -o BatchMode=yes \
    -o "ProxyCommand=${proxy_command}" \
    -o PubkeyAuthentication=no \
    -o PasswordAuthentication=no \
    -o KbdInteractiveAuthentication=no \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "${target_user}@just-sshd.test" id -un 2>/dev/null)"

test "${actual_user}" = "${target_user}"
