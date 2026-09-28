#!/bin/sh
set -eu

test_dir=$(dirname "$0")
sh "$test_dir/user_namespace.sh"
sh "$test_dir/codex_sandbox.sh"
