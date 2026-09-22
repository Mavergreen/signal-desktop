# Build ingredients

`mavericks-signal-desktop` is a Porthole **preset** that ports Signal-Desktop. The shipped `.pkg` is
tiny -- just the preset conf (`signal-desktop.conf`) + install scripts -- so most of what a user runs
(the container image, the launcher) is rendered on their Mac by `porthole materialize`, not baked here.

| Ingredient | Pinned in | Renovate | On a bump |
|---|---|---|---|
| Signal-Desktop (own upstream) | `UPSTREAM_VERSION` | github-releases on `signalapp/Signal-Desktop` (stable only) | `release.yml` on push to main auto-cuts `<version>-mavericks.1` |
| Porthole engine (runtime prerequisite) | not baked — `preinstall` requires it installed | github-actions manager (the `@v1` install action used in CI) | user updates Porthole itself (Sparkle) |
| shipyard (release tooling + gate) | `Mavergreen/shipyard@v1` (install action) | github-actions manager tracks the `@v1` tag | `@v1` is a moving tag |

The container is `UPDATE=float` (see `signal-desktop.conf`): it installs whatever Signal currently
ships (their apt repo is latest-only), so the pin never goes stale on a user's machine. `UPSTREAM_VERSION`
names the release for the Signal version current at release time; it does not hard-pin apt.
