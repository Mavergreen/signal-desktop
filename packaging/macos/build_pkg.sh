#!/bin/sh
# platform: macOS-only -- pkgbuild and productbuild assemble the pkg
#   usage: build_pkg.sh <version> <out.pkg>
#          The Signal preset: its conf in the product's tree. Its postinstall asks the installed
#          Porthole to materialize "Linux Signal Desktop.app", which the manifest declares as
#          generated so uninstall removes it.
set -eu
VERSION=$1; OUT=$2
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
. "$REPO/build/msc.sh"

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sig-preset.XXXXXX")
P="$ROOT/usr/local/mavergreen/signal-desktop/share/porthole/presets"
install -d "$P"
install -m 0644 "$REPO/signal-desktop.conf" "$P/signal-desktop.conf"
if [ -f "$REPO/signal-desktop.menu.json" ]; then install -m 0644 "$REPO/signal-desktop.menu.json" "$P/signal-desktop.menu.json"; fi

SCR=$(mktemp -d "${TMPDIR:-/tmp}/sig-scripts.XXXXXX")
sh "$SHIPYARD/stage_product.sh" --stage "$ROOT" --product signal-desktop --name "Signal Desktop for Mavericks" \
  --version "$VERSION" --generated "Applications/Linux Signal Desktop.app" \
  --preinstall-hook "$HERE/preinstall-hook.sh" --postinstall-hook "$HERE/postinstall-hook.sh" \
  --scripts-out "$SCR"

COMPONENT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sig-pkg.XXXXXX")
pkgbuild --root "$ROOT" --identifier dev.mavergreen.signal-desktop --version "$VERSION" \
    --scripts "$SCR" --install-location / "$COMPONENT_DIR/mavericks-signal-desktop-component.pkg"

mkdir -p "$(dirname "$OUT")"
sh "$SHIPYARD/set_install_floor.sh" --identifier dev.mavergreen.signal-desktop --title "Signal Desktop for Mavericks" \
  --component "$COMPONENT_DIR/mavericks-signal-desktop-component.pkg" --out "$OUT" --require-scripts >&2

echo "Built $OUT"
