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

@test "the package requires Porthole, through shipyard's generated check" {
  grep -q -- '--requires porthole' "$REPO/packaging/macos/build_pkg.sh"
}

@test "no hand-written requirement check is left to drift" {
  [ ! -e "$REPO/packaging/macos/preinstall-hook.sh" ] || return 1
  ! grep -q -- '--preinstall-hook' "$REPO/packaging/macos/build_pkg.sh" || return 1
}

# The app must exist for the install to count; only the build may be left to the first launch.
@test "postinstall fails when the app can't be materialized" {
  e="$WORK/v/Applications/Porthole.app/Contents/Resources/engine/bin"; mkdir -p "$e"
  printf '#!/bin/sh\n[ "$1" = materialize ] && exit 1\nexit 0\n' > "$e/porthole"; chmod +x "$e/porthole"
  run env ROOT="$WORK/v" sh "$REPO/packaging/macos/postinstall-hook.sh"
  [ "$status" -ne 0 ]
}

@test "postinstall materializes the preset from its tree with the target volume's engine" {
  e="$WORK/v/Applications/Porthole.app/Contents/Resources/engine/bin"; mkdir -p "$e"
  printf '#!/bin/sh\necho "$@" >> "%s/args"\n' "$WORK" > "$e/porthole"; chmod +x "$e/porthole"
  run env ROOT="$WORK/v" sh "$REPO/packaging/macos/postinstall-hook.sh"
  [ "$status" -eq 0 ]
  c="$WORK/v/usr/local/mavergreen/signal-desktop/share/porthole/presets/signal-desktop.conf"
  [ "$(sed -n 1p "$WORK/args")" = "materialize $c --apps-dir $WORK/v/Applications" ] || { cat "$WORK/args"; return 1; }
  # ...then builds the app in its own window before Installer finishes (Porthole skips this on another volume).
  [ "$(sed -n 2p "$WORK/args")" = "prepare-for-install --root $WORK/v --apps-dir $WORK/v/Applications $c" ] || { cat "$WORK/args"; return 1; }
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

# The release's version goes into the installed conf, so each release changes the app's recipe and
# its install rebuilds the Linux app with the newest package.
@test "the installed conf names the release's version" {
  sh "$REPO/packaging/macos/build_pkg.sh" 0.0.0 "$WORK/out.pkg" >/dev/null
  pkgutil --expand "$WORK/out.pkg" "$WORK/x"
  mkdir -p "$WORK/t"; (cd "$WORK/t" && gzip -dc "$WORK/x/mavericks-signal-desktop-component.pkg/Payload" | cpio -id --quiet)
  [ "$(tail -n 1 "$WORK/t/usr/local/mavergreen/signal-desktop/share/porthole/presets/signal-desktop.conf")" = APP_VERSION=0.0.0 ]
}

# A stand-in for the updater mavericks_add_updater_app builds: the identity and feed shipyard's registry
# gives signal-desktop, which stage_product.sh checks.
stub_updater() {
  u="$WORK/signal-desktop-updater.app"; mkdir -p "$u/Contents/MacOS"
  printf '#!/bin/sh\n' > "$u/Contents/MacOS/signal-desktop-updater"; chmod +x "$u/Contents/MacOS/signal-desktop-updater"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string dev.mavergreen.signal-desktop.updater' \
    -c 'Add :CFBundleExecutable string signal-desktop-updater' \
    -c 'Add :SUFeedURL string https://github.com/Mavergreen/signal-desktop/releases/latest/download/signal-desktop.xml' \
    "$u/Contents/Info.plist" >/dev/null
  printf '%s' "$u"
}

# Releases reach an installed preset the way Porthole's do: a daily check, then an offer to install.
@test "with UPD_APP, the pkg carries signal-desktop's updater and its daily check" {
  run env UPD_APP="$(stub_updater)" sh "$REPO/packaging/macos/build_pkg.sh" 0.0.0 "$WORK/out.pkg"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  pkgutil --expand "$WORK/out.pkg" "$WORK/x"
  files="$(lsbom -s "$WORK/x/mavericks-signal-desktop-component.pkg/Bom")"
  echo "$files" | grep -q 'Library/Application Support/Mavergreen/signal-desktop-updater.app/Contents/Info.plist$' || { echo "$files"; return 1; }
  echo "$files" | grep -q 'updatecheck.plist$' || { echo "$files"; return 1; }
}

@test "UPD_APP naming no updater fails the build" {
  run env UPD_APP="$WORK/nothing-here.app" sh "$REPO/packaging/macos/build_pkg.sh" 0.0.0 "$WORK/out.pkg"
  [ "$status" -ne 0 ] || return 1
  [[ "$output" == *"no updater .app"* ]] || false
}
