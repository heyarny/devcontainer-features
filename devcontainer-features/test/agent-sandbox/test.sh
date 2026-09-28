#!/bin/sh
set -eu

command -v bwrap >/dev/null
bwrap --version
