#!/usr/bin/env bats
# mavericks-signal-desktop is a Porthole PRESET: the .pkg ships only the Signal parameter set
# (signal-desktop.conf); installing it asks the Porthole engine to materialize "Linux Signal Desktop.app".
# There is no viewer build here.

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  PORTHOLE_REPO="${PORTHOLE_DIR:-$REPO/../mavergreen-porthole}"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/sig-preset-test.XXXXXX")"
}
teardown() { [ -n "$WORK" ] && rm -rf "$WORK"; }

@test "the preset .pkg ships the Signal conf under the family's Porthole presets dir" {
  run sh "$REPO/packaging/macos/build_pkg.sh" 0.0.0 "$WORK/out.pkg"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  pkgutil --payload-files "$WORK/out.pkg" \
    | grep -q 'Library/Application Support/Mavergreen/Porthole/presets/signal-desktop.conf'
}

@test "the .pkg declares a 10.9.5 minimum" {
  sh "$REPO/packaging/macos/build_pkg.sh" 0.0.0 "$WORK/out.pkg" >/dev/null
  pkgutil --expand "$WORK/out.pkg" "$WORK/x"
  grep -q 'os-version min="10.9.5"' "$WORK/x/Distribution"
}

@test "preinstall refuses to install when Porthole is absent" {
  # Point the (hardcoded) checks at guaranteed-absent paths, then assert it rejects.
  sed 's#/usr/local/bin/porthole#/nope/porthole#g; s#/Applications/Porthole.app#/nope/Porthole.app#g' \
    "$REPO/packaging/macos/scripts/preinstall" > "$WORK/pre"; chmod 755 "$WORK/pre"
  run sh "$WORK/pre"
  [ "$status" -ne 0 ]
  [[ "$output" == *"needs Porthole installed"* ]] || false
}

@test "postinstall invokes porthole materialize on the installed conf" {
  grep -q 'materialize' "$REPO/packaging/macos/scripts/postinstall"
  grep -q '/Library/Application Support/Mavergreen/Porthole/presets/signal-desktop.conf' "$REPO/packaging/macos/scripts/postinstall"
}

@test "materialize turns the preset conf into Linux Signal Desktop.app" {
  [ -x "$PORTHOLE_REPO/bin/porthole" ] || skip "porthole engine not available as a sibling"
  PORTHOLE_MATERIALIZE_NO_ICON=1 "$PORTHOLE_REPO/bin/porthole" \
    materialize "$REPO/signal-desktop.conf" --apps-dir "$WORK/apps"
  [ -d "$WORK/apps/Linux Signal Desktop.app" ]
  [ -x "$WORK/apps/Linux Signal Desktop.app/Contents/Resources/bin/signal-desktop" ]
  grep -q 'Applications/Porthole.app' "$WORK/apps/Linux Signal Desktop.app/Contents/Resources/bin/signal-desktop"
  [ -f "$WORK/apps/Linux Signal Desktop.app/Contents/Resources/signal-desktop/Dockerfile" ]
}

# Signal keeps its database key in Electron's safeStorage, whose backend Electron picks from the
# desktop environment. Under xpra that's "Xpra", which it doesn't recognize; left to choose, it used
# a plaintext key, then a different desktop made it migrate the key into the GNOME keyring and the
# next normal launch couldn't open the database (2026-09-25). Pin the backend the container provides:
# its child script runs a passwordless gnome-keyring for exactly this.
@test "Signal is launched with its key store pinned to the container's GNOME keyring" {
  [ -x "$PORTHOLE_REPO/bin/porthole" ] || skip "porthole engine not available as a sibling"
  PORTHOLE_MATERIALIZE_NO_ICON=1 "$PORTHOLE_REPO/bin/porthole" \
    materialize "$REPO/signal-desktop.conf" --apps-dir "$WORK/apps" >/dev/null
  ch="$WORK/apps/Linux Signal Desktop.app/Contents/Resources/signal-desktop/signal-desktop-child.sh"
  grep -q '^exec signal-desktop .*--password-store=gnome-libsecret' "$ch" || { grep '^exec' "$ch"; return 1; }
  grep -q 'gnome-keyring-daemon --unlock' "$ch"
}
