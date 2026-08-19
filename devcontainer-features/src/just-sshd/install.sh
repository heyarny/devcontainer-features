#!/bin/sh

set -eu

resolve_automatic_user() {
    candidate="${_REMOTE_USER:-${_CONTAINER_USER:-}}"

    case "${candidate}" in
        ''|auto|automatic|none|root)
            candidate=""
            ;;
    esac

    if [ -n "${candidate}" ] && id "${candidate}" >/dev/null 2>&1; then
        printf '%s\n' "${candidate}"
        return 0
    fi

    for candidate in vscode node codespace; do
        if id "${candidate}" >/dev/null 2>&1; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done

    awk -F: '$3 >= 1000 && $3 < 60000 && $7 !~ /(nologin|false)$/ { print $1; exit }' /etc/passwd
}

target_user="${USERNAME:-automatic}"
case "${target_user}" in
    auto|automatic)
        target_user="$(resolve_automatic_user)"
        ;;
esac

case "${target_user}" in
    ''|*[!A-Za-z0-9._-]*)
        echo "just-sshd requires a valid existing Linux username." >&2
        exit 1
        ;;
esac

if ! id "${target_user}" >/dev/null 2>&1; then
    echo "just-sshd user does not exist: ${target_user}" >&2
    exit 1
fi

if [ "$(id -u "${target_user}")" -eq 0 ]; then
    echo "just-sshd refuses unauthenticated root access. Configure a non-root remoteUser or set the username option." >&2
    exit 1
fi

install -d -m 0755 /etc/ssh/sshd_config.d

# OpenSSH's initial "none" request succeeds only for an empty password when
# password authentication and PermitEmptyPasswords are both enabled.
passwd -d "${target_user}"

cat >/etc/ssh/sshd_config.d/00-just-sshd.conf <<EOF
ListenAddress 127.0.0.1
PermitRootLogin no
AllowUsers ${target_user}
PasswordAuthentication yes
PermitEmptyPasswords yes
KbdInteractiveAuthentication no
PubkeyAuthentication no
UsePAM no
EOF

/usr/sbin/sshd -t

echo "Configured unauthenticated local SSH access for ${target_user}."
echo "Use sshd -i through a host ProxyCommand; no host port is required."
