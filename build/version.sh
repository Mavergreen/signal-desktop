#!/bin/sh
# platform: host-agnostic
# Thin wrapper over shipyard's version logic. UPSTREAM_VERSION is the Signal-Desktop version;
# version.sh turns it into <version>-mavericks.N and decides whether to release.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
MAVERICKS_ROOT="$(cd "$SELF/.." && pwd)"; export MAVERICKS_ROOT
. "$SELF/msc.sh"
exec sh "$SHIPYARD/version.sh" "$@"
