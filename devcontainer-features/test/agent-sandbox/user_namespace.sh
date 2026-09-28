#!/bin/sh
set -eu

if [ "$(id -u)" -eq 0 ]; then
    su -s /bin/sh vscode -c 'bwrap --unshare-user --uid 0 --gid 0 --ro-bind / / --dev /dev --proc /proc -- sh -c "test \"$(id -u)\" -eq 0"'
else
    bwrap --unshare-user --uid 0 --gid 0 --ro-bind / / --dev /dev --proc /proc -- sh -c 'test "$(id -u)" -eq 0'
fi
