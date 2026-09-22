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

# ONE-TIME MIGRATION off the ModernMavericks identity (flag day 2026-09-22).
# DELETABLE with packaging/macos/scripts/flag-day-migration (see shipyard SKILL.md "Consolidation backlog").
fake_pkgutil() {
  mkdir -p "$WORK/stubs"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexit %s\n' "$WORK/pkgutil.log" "${1:-0}" > "$WORK/stubs/pkgutil"
  chmod 755 "$WORK/stubs/pkgutil"
}
old_presets() { printf '%s' "$WORK/vol/Library/Application Support/Porthole/presets"; }
migrate() { PATH="$WORK/stubs:$PATH" run sh "$REPO/packaging/macos/scripts/flag-day-migration" "$@"; }

@test "the pkg ships the flag-day migration and postinstall runs it with Installer's arguments" {
  sh "$REPO/packaging/macos/build_pkg.sh" 0.0.0 "$WORK/out.pkg" >/dev/null
  pkgutil --expand "$WORK/out.pkg" "$WORK/x"
  [ -x "$WORK/x/mavericks-signal-desktop-component.pkg/Scripts/flag-day-migration" ] \
    || { echo "flag-day-migration is not in the pkg's Scripts, so postinstall cannot run it"; return 1; }
  grep -q 'sh "$(dirname "$0")/flag-day-migration" "$@"' "$REPO/packaging/macos/scripts/postinstall" \
    || { echo "postinstall does not pass its own \$@ (so \$3, the target volume) to flag-day-migration"; return 1; }
}

@test "flag-day migration removes this preset's old files, keeps other presets, forgets the old receipt" {
  fake_pkgutil 0
  mkdir -p "$(old_presets)"
  for f in signal-desktop.conf signal-desktop.menu.json other-app.conf; do : > "$(old_presets)/$f"; done
  migrate pkg "$WORK/vol" "$WORK/vol" "$WORK/vol"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ ! -e "$(old_presets)/signal-desktop.conf" ] || { echo "old signal-desktop.conf left at the pre-flag-day path"; return 1; }
  [ ! -e "$(old_presets)/signal-desktop.menu.json" ] || { echo "old signal-desktop.menu.json left at the pre-flag-day path"; return 1; }
  [ -e "$(old_presets)/other-app.conf" ] || { echo "removed ANOTHER preset's file: only our own names may go"; return 1; }
  grep -qx -- "--volume $WORK/vol --forget dev.modernmavericks.signal-desktop" "$WORK/pkgutil.log" \
    || { echo "old receipt not forgotten on the target volume; pkgutil saw: $(cat "$WORK/pkgutil.log" 2>/dev/null)"; return 1; }
}

@test "flag-day migration removes the old preset dirs once they are empty" {
  fake_pkgutil 0
  mkdir -p "$(old_presets)"; : > "$(old_presets)/signal-desktop.conf"
  migrate pkg "$WORK/vol" "$WORK/vol" "$WORK/vol"
  [ "$status" -eq 0 ] || return 1
  [ ! -e "$WORK/vol/Library/Application Support/Porthole" ] \
    || { echo "the emptied pre-flag-day Porthole dir was left behind"; return 1; }
  [ -d "$WORK/vol/Library/Application Support" ] || { echo "removed more than the Porthole dir"; return 1; }
}

@test "flag-day migration touches nothing without a target volume, and never fails the install" {
  fake_pkgutil 1
  mkdir -p "$(old_presets)"; : > "$(old_presets)/signal-desktop.conf"
  migrate
  [ "$status" -eq 0 ] || return 1
  [ ! -f "$WORK/pkgutil.log" ] || { echo "forgot a receipt with no target volume"; return 1; }
  [ -e "$(old_presets)/signal-desktop.conf" ] || { echo "removed a file with no target volume"; return 1; }
  migrate pkg "$WORK/vol" "$WORK/vol" "$WORK/vol"
  [ "$status" -eq 0 ] || { echo "a failing pkgutil failed the install"; return 1; }
}
