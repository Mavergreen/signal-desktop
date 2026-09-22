#!/bin/sh
# Build the mavericks-signal-desktop PRESET .pkg. A preset ships only the Signal parameter set
# (signal-desktop.conf, + an optional menu.json); its postinstall asks the installed Porthole engine
# to materialize "Linux Signal Desktop.app" on the Mac (the whole container recipe + launcher are rendered
# there from templates by `porthole materialize`). No compiler, no viewer, no container here.
# Usage: build_pkg.sh <version> <out.pkg>
set -eu
VERSION=$1; OUT=$2
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sig-preset.XXXXXX")
PRESETS="$ROOT/Library/Application Support/Mavergreen/Porthole/presets"
install -d "$PRESETS"
install -m 0644 "$REPO/signal-desktop.conf" "$PRESETS/signal-desktop.conf"
[ -f "$REPO/signal-desktop.menu.json" ] && install -m 0644 "$REPO/signal-desktop.menu.json" "$PRESETS/signal-desktop.menu.json"

COMPONENT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sig-pkg.XXXXXX")
mkdir -p "$(dirname "$OUT")"
pkgbuild --root "$ROOT" \
    --identifier dev.mavergreen.signal-desktop \
    --version "$VERSION" \
    --scripts "$HERE/scripts" \
    --install-location / \
    "$COMPONENT_DIR/mavericks-signal-desktop-component.pkg"

productbuild --distribution "$HERE/distribution.xml" \
    --package-path "$COMPONENT_DIR" \
    "$OUT"

echo "Built $OUT"
