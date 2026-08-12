# Contributing to MellowDesk

Thank you for helping improve MellowDesk. Focused bug fixes, tests, accessibility improvements, privacy improvements, and clear documentation changes are welcome.

Please follow the [Code of Conduct](CODE_OF_CONDUCT.md) in all project spaces.

## Before you start

- Search existing issues and pull requests before opening a duplicate.
- For a large feature, data-model change, permission change, or new reminder module, discuss the scope in an issue first.
- Keep the current beta honest: NeckEase is implemented; hydration, stand-up, lunch, and takeout reminders are roadmap items only.
- Never use real faces, camera recordings, personal health information, or workout-history files as fixtures.

## Development requirements

- macOS 13 or later.
- A full Xcode installation compatible with Swift 5.10.
- No third-party dependency is required for the current package.

Run the full local check:

```bash
./Scripts/check.sh
```

The check validates property lists, runs swift-format when available, executes the 45 deterministic tests, builds the release product, and assembles `build/MellowDesk.app`.

For a faster development launch:

```bash
./Scripts/run_debug.sh
```

## Change guidelines

### Code

- Prefer a small, direct change over a speculative abstraction.
- Keep camera ownership and Vision processing local to the app.
- Do not add networking, analytics, telemetry, or persistent frame/pose storage without an explicit product decision and a privacy-policy update.
- Add deterministic tests for counting, calibration, scheduling, statistics, or face-selection behavior.
- Camera lifecycle changes also require a real MacBook check using [docs/TEST_CHECKLIST.md](docs/TEST_CHECKLIST.md).

### Exercise content

Exercise text is product content, not incidental UI copy. A change to movements, repetitions, hold times, or safety wording must:

1. explain the intended user benefit;
2. cite an authoritative public source or relevant review;
3. distinguish recognition thresholds from exercise dose and medical range of motion;
4. update [docs/EXERCISE_CONTENT.md](docs/EXERCISE_CONTENT.md);
5. add or update deterministic tests;
6. bump the routine version when saved-history interpretation changes.

Do not add diagnosis, treatment promises, individualized rehabilitation claims, or copied third-party illustrations.

### Documentation

- Keep `README.md` and `README.zh-CN.md` aligned.
- Use **MellowDesk / 小桌伴** for the app and mother brand.
- Use **NeckEase / 颈间** for the current neck-movement module.
- Mark unimplemented roadmap features as unimplemented.
- Update `CHANGELOG.md` for user-visible behavior.

## Pull request checklist

- [ ] The change has one clear purpose.
- [ ] `./Scripts/check.sh` passes locally, or the exact blocker is documented.
- [ ] New behavior has tests proportional to its risk.
- [ ] Camera or notification behavior was manually checked when relevant.
- [ ] Privacy, exercise-content, and bilingual README text are updated when relevant.
- [ ] No face, video, raw pose sample, personal history, secret, or generated build artifact is committed.

## Bug reports

Include:

- macOS version and Mac model;
- MellowDesk version or commit;
- expected and observed behavior;
- reproduction steps;
- whether manual counting works;
- for counting issues, the movement name and `actual repetitions / app repetitions`.

Do not attach privacy-sensitive media or data. Security and privacy vulnerabilities must use the private process in [SECURITY.md](SECURITY.md).

## License of contributions

Unless you explicitly state otherwise, a contribution intentionally submitted to this project is provided under the [Apache License 2.0](LICENSE), consistent with Section 5 of that license.
