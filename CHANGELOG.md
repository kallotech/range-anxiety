# Changelog

All notable changes are recorded here.

Versions before `0.6.0` are documented retrospectively. Exact source snapshots were not preserved before Git history was initialized, so public releases and source tags begin with `v0.6.0`.

## [Unreleased]

- Added the custom RangeAnxiety application icon, with transparent standard and Retina representations generated from the supplied artwork.
- Fixed Settings opening behind other applications. Clicking the gear now activates the app and brings its Settings window forward, including when already open or minimized, without making it always-on-top.

## [0.6.0] - 2026-09-01

- Renamed the user-facing app and build product to RangeAnxiety.
- Adopted the final `io.github.kallotech.rangeanxiety` bundle identifier with migration of existing local preferences.
- Moved provider credentials from owner-only plaintext files to encrypted macOS Keychain storage.
- Added verified migration and removed old credential files only after successful Keychain readback.
- Prevented background Keychain access from opening password dialogs.
- Added a Buy Me a Coffee link to General Settings.
- Removed the unreliable Codex daily-token figure from provider cards and combined reporting coverage.
- Added stable local-signing support and an intentional one-time Keychain authorization flow for signing-identity upgrades.

## [0.5.1] - 2026-09-01

- Made fast-usage streaks slightly more visible and allowed them to extend beyond the filled quota bar.
- Added a subtle blue-to-muted-red shift during rapid quota use.

## [0.5.0] - 2026-09-01

- Added burn-rate-aware quota animations with support for Reduce Motion.

## [0.4.2] - 2026-09-01

- Simplified the Providers settings page.

## [0.4.1] - 2026-09-01

- Replaced system drag-and-drop with reliable in-popover card reordering.

## [0.4.0] - 2026-09-01

- Added the provider catalog, centralized connector settings, draggable usage cards, and period-aware totals.

## [0.3.1] - 2026-08-29

- Restored Codex quota bars.
- Removed the unstable Keychain dependency from local ad-hoc builds.
