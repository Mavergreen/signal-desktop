#!/usr/bin/env bats
# platform: host-agnostic
# The Signal preset's install scripts, its requirement and its conf, on any host. What reads the built
# .pkg or materializes the app is in test_signal-desktop.bats, macOS-only.

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/sig-preset-test.XXXXXX")"
}
teardown() { [ -n "$WORK" ] && rm -rf "$WORK"; }

@test "the package requires a Porthole that hands the app its links, through shipyard's generated check" {
  grep -qF -- "--requires 'porthole>=20261121.0'" "$REPO/packaging/macos/build_pkg.sh"
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

@test "UPD_APP naming no updater fails the build" {
  run env UPD_APP="$WORK/nothing-here.app" sh "$REPO/packaging/macos/build_pkg.sh" 0.0.0 "$WORK/out.pkg"
  [ "$status" -ne 0 ] || return 1
  [[ "$output" == *"no updater .app"* ]] || false
}

# Bad arguments are refused before anything slow or fallible runs (locating shipyard runs cmake), so
# the refusal is the same whatever state shipyard is in -- 1Password's copy flaked once when it wasn't.
@test "UPD_APP naming no updater fails the build even when shipyard can't be located" {
  mkdir -p "$WORK/fakebin"
  printf '#!/bin/sh\necho "refused" >&2\nexit 1\n' > "$WORK/fakebin/shipyard-cmake"; chmod +x "$WORK/fakebin/shipyard-cmake"
  run env -i HOME="$HOME" TMPDIR="$WORK" PATH="$WORK/fakebin:/usr/bin:/bin" UPD_APP="$WORK/nothing-here.app" \
    sh "$REPO/packaging/macos/build_pkg.sh" 0.0.0 "$WORK/out.pkg"
  [ "$status" -ne 0 ] || return 1
  [[ "$output" == *"no updater .app"* ]] || { echo "$output"; false; }
}

@test "build_pkg.sh leaves no temporary directories behind" {
  mkdir -p "$WORK/tmp"
  run env TMPDIR="$WORK/tmp" sh "$REPO/packaging/macos/build_pkg.sh" 0.0.0 "$WORK/out.pkg"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -z "$(ls "$WORK/tmp")" ] || { ls "$WORK/tmp"; false; }
  run env TMPDIR="$WORK/tmp" UPD_APP="$WORK/nothing-here.app" sh "$REPO/packaging/macos/build_pkg.sh" 0.0.0 "$WORK/out2.pkg"
  [ "$status" -ne 0 ] || return 1
  [ -z "$(ls "$WORK/tmp")" ] || { ls "$WORK/tmp"; false; }
}

# The schemes Signal's Linux package registers: its signal-desktop.desktop has
#   MimeType=x-scheme-handler/sgnl;x-scheme-handler/signalcaptcha;
# so a signal.me link opens the conversation, and a registration captcha's callback reaches the app.
@test "the app takes the URL schemes Signal's Linux package registers" {
  [ "$( . "$REPO/signal-desktop.conf"; printf '%s' "$URL_SCHEMES")" = 'sgnl signalcaptcha' ]
}
