# mavericks-signal-desktop

A [Porthole](https://github.com/Mavergreen/porthole) **preset** that runs Signal Desktop on
OS X 10.9 (Mavericks) as a native-feeling "Linux Signal Desktop.app".

This repo is not a viewer build -- it ships a single parameter set (`signal-desktop.conf`). Install
Porthole once, then install this preset's `.pkg`: its postinstall runs `porthole materialize`, which
renders the Signal container recipe + launcher and drops **Linux Signal Desktop.app** into `/Applications`.
On first launch the container image builds and the app runs in the Porthole viewer.

- **Prerequisite:** Porthole must be installed first (`preinstall` enforces it).
- **Version:** `<signal-version>-mavericks.N`, tracking `signalapp/Signal-Desktop` stable releases.
- **Updates:** the container floats to the latest Signal at first launch (Signal's apt repo is
  latest-only), so it never goes stale.
