# MellowDesk 小桌伴

[Simplified Chinese / 简体中文](README.zh-CN.md)

<p align="center">
  <img src="docs/assets/app-icon.png" alt="MellowDesk app icon" width="120">
</p>

> A quiet macOS companion that helps you feel better during the workday.

**Open-source beta · macOS 13+ · Apache-2.0**

MellowDesk is a native menu-bar companion with one low-interruption work-break plan that rotates stand-up movement, hydration, and a guided neck-and-shoulder routine.

```text
unified reminder rhythm → stand / hydrate / neck break → local history
```

There are no accounts, cloud sync, ads, analytics, or telemetry. Camera use begins only after you start a routine, and manual counting is always available.

## What this beta includes

- A menu-bar companion with configurable workdays, work hours, reminder intervals, sound, snooze, pause, and launch at login.
- A persistent reminder anchored to the menu-bar leaf that waits for Start, Snooze, or Pause instead of disappearing after a few seconds.
- Local notifications with **Start** and **Snooze 10 minutes** actions.
- A single default 50-minute rhythm rotating stand-up movement, hydration with movement, and the neck routine, with only one card at a time.
- A two-minute movement guide and lightweight hydration check-ins without fixed-volume targets.
- The NeckEase routine: slow left/right rotation, gentle left/right lateral flexion, and a gentle nod back to neutral.
- Animated guidance, current direction, target repetitions, hold/return feedback, and completion results.
- On-device head-pose counting with neutral calibration, per-movement direction adaptation, filtering, hysteresis, and complete return-to-neutral checks.
- Manual counting when camera permission is declined, the camera is unavailable, or recognition is unreliable.
- Local-only daily, 7-day, and 30-day history by activity type.

## Privacy in one minute

- Camera frames are processed in memory with Apple frameworks. They are not recorded, saved, or uploaded.
- MellowDesk stores settings, workout summaries, and stand/hydration completion times on this Mac. It does not store images, face templates, audio, or frame-by-frame head angles.
- The app has no network entitlement and contains no account, cloud, advertising, analytics, or telemetry integration.
- History can be cleared from Settings at any time.

Read the complete [Privacy Policy](PRIVACY.md) before reporting privacy-sensitive issues.

## Exercise scope

NeckEase is a short activity reminder for general adult office use. It is not a medical device and does not provide diagnosis, treatment, or an individualized rehabilitation plan. Move slowly within a comfortable range and stop if the movement causes discomfort.

The camera thresholds are approximate recognition thresholds, not medical range-of-motion targets or exercise prescriptions. See [Exercise Content and Evidence](docs/EXERCISE_CONTENT.md) for the routine version, doses, recognition behavior, sources, and content-governance rules.

## Requirements

- macOS 13 or later.
- A camera is optional; manual counting remains available.

A full Xcode installation compatible with Swift 5.10 is required only when building from source.

## Download

Download the notarized universal macOS build from the
[v0.1.0-beta.3 release](https://github.com/EigenLogic/MellowDesk/releases/tag/v0.1.0-beta.3).
The release includes a SHA-256 checksum file. The app is signed by EigenLogic with Developer ID,
uses Hardened Runtime, and is notarized by Apple.

## Build from source

Local source builds use ad-hoc signing and are separate from the notarized GitHub Release.

Build and open the app:

```bash
./Scripts/run_debug.sh
```

Run all automated checks and assemble the app:

```bash
./Scripts/check.sh
```

The app is assembled at `build/MellowDesk.app` with bundle identifier `cn.eigenlogic.mellowdesk`.

## First run

1. Open `MellowDesk.app` and allow notifications if you want scheduled reminders.
2. The default workday plan rotates stand, hydration, and neck reminders; each activity can also be started from the menu bar.
3. For the neck routine, start the camera session or switch to manual counting.
4. Face the screen briefly to establish a neutral pose.
5. Before each movement, complete one small, uncounted adaptation movement and return to neutral.
6. Follow the animation. A repetition counts only after the target hold and a visible return to neutral.

## Known beta limitations

- Camera counting is intentionally approximate and varies with camera model, lighting, framing, and individual movement.
- The first beta has Chinese app UI; English project documentation does not imply English UI localization.
- Source-built apps use local ad-hoc signing; the official GitHub Release is Developer ID signed and notarized.
- At least one real MacBook camera pass is required in addition to automated tests; use the [Real-camera Test Checklist](docs/TEST_CHECKLIST.md).

## Project layout

```text
Sources/MellowDeskCore       movement, calibration, counting, statistics, schedule rules
Sources/MellowDesk           app lifecycle, camera, services, view models, and SwiftUI views
Tests/MellowDeskCoreTests    deterministic core tests
Tests/MellowDeskTests        app-level deterministic tests
Resources                    Info.plist, sandbox entitlements, and privacy manifest
Scripts                      checks, app assembly, and local launch
docs                         product, technical, exercise, test, and release documentation
```

The repository currently contains **more than 60 deterministic tests**. Synthetic tests do not replace real-camera acceptance.

## Roadmap

Future modules may include:

- lunch and takeout reminders.

Roadmap items are exploratory and are not claims about current functionality.

## Project documents

- [Product Design](docs/PRODUCT_DESIGN.md)
- [Technical Design](docs/TECHNICAL_DESIGN.md)
- [Exercise Content and Evidence](docs/EXERCISE_CONTENT.md)
- [Real-camera Test Checklist](docs/TEST_CHECKLIST.md)
- [Release Process](docs/RELEASING.md)
- [Privacy Policy](PRIVACY.md)
- [Contributing](CONTRIBUTING.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Security Policy](SECURITY.md)
- [Changelog](CHANGELOG.md)
- [v0.1.0-beta.3 Release Notes](docs/releases/v0.1.0-beta.3.md)

## Contributing and security

Bug reports, documentation improvements, tests, and focused implementation changes are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Exercise-content changes have additional evidence and versioning requirements.

Please do not attach faces, camera recordings, raw pose data, or personal workout history to a public issue. Report security or privacy vulnerabilities through the private process in [SECURITY.md](SECURITY.md).

## License

Copyright 2026 EigenLogic and MellowDesk contributors.

Licensed under the [Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for attribution information.
