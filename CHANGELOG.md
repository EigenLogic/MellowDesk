# Changelog

This file records user-visible changes to MellowDesk. Dates use the YYYY-MM-DD format.

## Unreleased

- No unreleased user-visible changes recorded.

## [0.1.0-beta.2] - 2026-08-12

### Fixed

- The menu-bar “next reminder” countdown now updates while the menu stays open instead of freezing at the minute shown when it first appeared.

See the full [v0.1.0-beta.2 release notes](docs/releases/v0.1.0-beta.2.md).

## [0.1.0-beta.1] - 2026-08-11

### Added

- The first MellowDesk open-source beta with the NeckEase module.
- Configurable workday reminders, notification actions, snooze, pause, sound, and launch at login.
- A three-movement animated routine: neck rotation, lateral flexion, and gentle nod.
- Optional on-device camera counting with neutral calibration, direction adaptation, filtering, hold/return validation, and manual fallback.
- Adaptive 5–8° recognition threshold for the gentle nod based on the stable demonstration peak.
- Local daily, 7-day, and 30-day completion history with clear-history controls.
- App Sandbox, camera-only device entitlement, and an Apple privacy manifest.
- A universal arm64 + x86_64 public build with EigenLogic Developer ID signing, Hardened Runtime, Apple notarization, and a published SHA-256 checksum.
- 32 deterministic automated tests and a real-camera acceptance checklist.
- English and Simplified Chinese public documentation, privacy, contribution, conduct, security, exercise-content, and release documents.

### Known limitations

- The app UI is Chinese in this beta.
- Camera counting is approximate and varies by environment and device.
- Local source builds are ad-hoc signed and are distinct from the official notarized GitHub Release.

See the full [v0.1.0-beta.1 release notes](docs/releases/v0.1.0-beta.1.md).
