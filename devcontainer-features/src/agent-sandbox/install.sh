#!/bin/sh
set -eu

if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends bubblewrap
elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache bubblewrap
else
    echo "agent-sandbox requires apt-get or apk." >&2
    exit 1
fi
