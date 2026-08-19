# Changelog

This file records user-visible changes to MellowDesk. Dates use the YYYY-MM-DD format.

## Unreleased

No unreleased user-visible changes recorded.

## [0.1.0-beta.6] - 2026-08-19

### Changed

- Pelvic-floor practice now joins the regular stand, hydration, and neck rotation when enabled. Completing the full guide writes a local completion used by daily totals, recent history, and 7/30-day activity statistics; skipping writes nothing.

### Fixed

- Active follow-alongs remain above other apps after MellowDesk loses focus, until the user completes, skips, or explicitly hides the activity.

See the full [v0.1.0-beta.6 release notes](docs/releases/v0.1.0-beta.6.md).

## [0.1.0-beta.5] - 2026-08-19

### Changed

- Neck, movement, hydration, and pelvic-floor follow-alongs now run inside a sticky menu-bar popover instead of separate activity windows.
- Every follow-along offers **Skip This Time**. Skipping writes no completion history and advances an active reminder to the next activity.

See the full [v0.1.0-beta.5 release notes](docs/releases/v0.1.0-beta.5.md).

## [0.1.0-beta.4] - 2026-08-14

### Added

- A unified work-break rotation for stand-up movement, hydration, and the existing neck-and-shoulder routine.
- A two-minute guided movement window, lightweight hydration check-ins, and local per-activity history.
- Activity-aware persistent cards, system notifications, menu-bar status, settings, dashboard totals, trends, and recent completions.
- A two-minute pelvic-floor follow-along, enabled by default and available directly from the menu bar, with an option to disable it in Settings. A ring of twelve bars contracts toward its center and back to pace each lift and release. It uses no camera or motion measurement, stays out of the reminder rotation, and writes no completion history. See [Exercise Content](docs/EXERCISE_CONTENT.md).
- Sparkle 2.9.5 updates, enabled by default: MellowDesk checks the signed appcast daily, downloads a newer GitHub Release ZIP in the background, verifies EdDSA and Developer ID signatures, then offers **Install and Relaunch** or **Later**. Later installs the ready update when the app quits, without opening a web page.

### Changed

- New installations start with a balanced 50-minute rhythm. Only one activity is due at a time; snoozing preserves that activity, while completion advances the rotation.
- Existing beta reminder state and neck-workout history remain readable.
- Beta.4 is the first Sparkle seed. Beta.3 to beta.4 remains the final manual installation; subsequent releases can update in app.

### Fixed

- Source and CI development apps now use the distinct `cn.eigenlogic.mellowdesk.dev` identity and Dev name, isolating their local data and macOS privacy permissions from the Developer ID signed release. Official releases continue to use `cn.eigenlogic.mellowdesk`.
- Camera authorization state, request, and outcome are now available in macOS unified logs, making failed permission flows diagnosable without recording camera frames or head-pose data.

See the full [v0.1.0-beta.4 release notes](docs/releases/v0.1.0-beta.4.md).

## [0.1.0-beta.3] - 2026-08-12

### Added

- A persistent reminder card anchored to the MellowDesk menu-bar icon, with Start, Snooze 10 minutes, and Pause Today actions.
- Durable overdue-reminder recovery across wake, app activation, clock changes, and app restarts.

### Fixed

- Reminders no longer disappear after the standard five-second macOS banner window.
- Starting a workout from the nonactivating reminder card now reliably brings the workout window to the front.
- Unique notification identifiers prevent a newly scheduled reminder from erasing the prior delivered notification.
- Each new reminder occurrence gets fresh interaction state, so later cycles remain actionable.
- Concurrent refreshes for the same due time no longer remove the current system fallback.

See the full [v0.1.0-beta.3 release notes](docs/releases/v0.1.0-beta.3.md).

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
