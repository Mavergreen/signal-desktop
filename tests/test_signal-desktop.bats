#!/usr/bin/env bats
# platform: macOS-only -- runs pkgutil
# mavericks-signal-desktop is a Porthole PRESET: the .pkg ships only the Signal parameter set
# (signal-desktop.conf); installing it asks the Porthole engine to materialize "Linux Signal Desktop.app".
# There is no viewer build here.

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  PORTHOLE_REPO="${PORTHOLE_DIR:-$REPO/../mavergreen-porthole}"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/sig-preset-test.XXXXXX")"
}
teardown() { [ -n "$WORK" ] && rm -rf "$WORK"; }

@test "the preset .pkg ships the conf in its tree, with a manifest" {
  run sh "$REPO/packaging/macos/build_pkg.sh" 0.0.0 "$WORK/out.pkg"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  pkgutil --expand "$WORK/out.pkg" "$WORK/x"
  files="$(lsbom -s "$WORK/x/mavericks-signal-desktop-component.pkg/Bom")"
  echo "$files" | grep -q 'usr/local/mavergreen/signal-desktop/share/porthole/presets/signal-desktop.conf$'
  echo "$files" | grep -q 'usr/local/mavergreen/signal-desktop/mavergreen.plist$'
  if echo "$files" | grep -q 'Library/Application Support/Mavergreen/Porthole'; then false; fi
}

@test "the .pkg declares a 10.9.5 floor and the base first" {
  sh "$REPO/packaging/macos/build_pkg.sh" 0.0.0 "$WORK/out.pkg" >/dev/null
  pkgutil --expand "$WORK/out.pkg" "$WORK/x"
  grep -q 'os-version min="10.9.5"' "$WORK/x/Distribution"
  [ "$(sed -n 's/.*<line choice="\([^"]*\)".*/\1/p' "$WORK/x/Distribution" | grep -v '^default$' | head -1)" = dev.mavergreen.base ]
  mkdir -p "$WORK/t"; (cd "$WORK/t" && gzip -dc "$WORK/x/mavericks-signal-desktop-component.pkg/Payload" | cpio -id --quiet)
  [ "$(/usr/libexec/PlistBuddy -c 'Print :generated:0' "$WORK/t/usr/local/mavergreen/signal-desktop/mavergreen.plist")" = "Applications/Linux Signal Desktop.app" ]
}

@test "preinstall refuses a volume without Porthole, naming it" {
  mkdir -p "$WORK/v"
  run env ROOT="$WORK/v" sh "$REPO/packaging/macos/preinstall-hook.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"needs Porthole installed"* ]] || false
}

@test "preinstall accepts a volume with Porthole" {
  mkdir -p "$WORK/v/usr/local/mavergreen/porthole"; : > "$WORK/v/usr/local/mavergreen/porthole/mavergreen.plist"
  run env ROOT="$WORK/v" sh "$REPO/packaging/macos/preinstall-hook.sh"
  [ "$status" -eq 0 ]
}

@test "postinstall materializes the preset from its tree with the target volume's engine" {
  e="$WORK/v/Applications/Porthole.app/Contents/Resources/engine/bin"; mkdir -p "$e"
  printf '#!/bin/sh\necho "$@" > "%s/args"\n' "$WORK" > "$e/porthole"; chmod +x "$e/porthole"
  run env ROOT="$WORK/v" sh "$REPO/packaging/macos/postinstall-hook.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$WORK/args")" = "materialize $WORK/v/usr/local/mavergreen/signal-desktop/share/porthole/presets/signal-desktop.conf --apps-dir $WORK/v/Applications" ]
}

@test "materialize turns the preset conf into Linux Signal Desktop.app" {
  [ -x "$PORTHOLE_REPO/bin/porthole" ] || skip "porthole engine not available as a sibling"
  PORTHOLE_MATERIALIZE_NO_ICON=1 PORTHOLE_ICON_CACHE="$WORK/sys-icons" PORTHOLE_USER_ICON_CACHE="$WORK/user-icons" "$PORTHOLE_REPO/bin/porthole" \
    materialize "$REPO/signal-desktop.conf" --apps-dir "$WORK/apps"
  [ -d "$WORK/apps/Linux Signal Desktop.app" ]
  [ -x "$WORK/apps/Linux Signal Desktop.app/Contents/Resources/bin/signal-desktop" ]
  grep -q 'Applications/Porthole.app' "$WORK/apps/Linux Signal Desktop.app/Contents/Resources/bin/signal-desktop"
  [ -f "$WORK/apps/Linux Signal Desktop.app/Contents/Resources/signal-desktop/Dockerfile" ] || return 1
  [ "$(cat "$WORK/apps/Linux Signal Desktop.app/Contents/Resources/AppIcon.width")" = 0 ]   # no cache: the penguin
}

# Signal keeps its database key in Electron's safeStorage, whose backend Electron picks from the
# desktop environment. Under xpra that's "Xpra", which it doesn't recognize; left to choose, it used
# a plaintext key, then a different desktop made it migrate the key into the GNOME keyring and the
# next normal launch couldn't open the database (2026-09-25). Pin the backend the container provides:
# its child script runs a passwordless gnome-keyring for exactly this.
@test "Signal is launched with its key store pinned to the container's GNOME keyring" {
  [ -x "$PORTHOLE_REPO/bin/porthole" ] || skip "porthole engine not available as a sibling"
  PORTHOLE_MATERIALIZE_NO_ICON=1 PORTHOLE_ICON_CACHE="$WORK/sys-icons" PORTHOLE_USER_ICON_CACHE="$WORK/user-icons" "$PORTHOLE_REPO/bin/porthole" \
    materialize "$REPO/signal-desktop.conf" --apps-dir "$WORK/apps" >/dev/null
  ch="$WORK/apps/Linux Signal Desktop.app/Contents/Resources/signal-desktop/signal-desktop-child.sh"
  grep -q '^exec signal-desktop .*--password-store=gnome-libsecret' "$ch" || { grep '^exec' "$ch"; return 1; }
  grep -q 'gnome-keyring-daemon --unlock' "$ch"
}
