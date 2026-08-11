# Releasing MellowDesk

This document covers the maintainer flow for a public GitHub beta. A public binary must be reproducible from a committed SHA, signed with Developer ID, hardened, notarized by Apple, stapled, and tested on a real MacBook.

## Release gates

Before creating a tag:

1. `./Scripts/check.sh` passes locally and CI passes on Apple Silicon and Intel runners.
2. [TEST_CHECKLIST.md](TEST_CHECKLIST.md) passes on a real MacBook.
3. `Info.plist`, `CHANGELOG.md`, and the release notes agree on the version.
4. The worktree is clean and the release commit is present on `main`.
5. The repository contains no secrets, personal history, face media, or generated build directories.

## One-time notarization setup

Store credentials in the login Keychain. Do not put credentials in this repository, shell history, an Issue, or a GitHub Release:

```bash
xcrun notarytool store-credentials mellowdesk-notary \
  --apple-id YOUR_APPLE_ID \
  --team-id YOUR_TEAM_ID
```

The command securely prompts for an app-specific password when `--password` is omitted.

## Build the public artifact

```bash
CODE_SIGN_IDENTITY="Developer ID Application: YOUR_ORGANIZATION (YOUR_TEAM_ID)" \
NOTARY_PROFILE=mellowdesk-notary \
RELEASE_VERSION=0.1.0-beta.1 \
APP_VERSION=0.1.0 \
BUILD_NUMBER=1 \
./Scripts/package_release.sh
```

The script enforces a Developer ID signature and an arm64 + x86_64 universal executable. Without `NOTARY_PROFILE`, it fails closed. `ALLOW_UNNOTARIZED=1` is only for a local test candidate and must never be used for a public Release.

Successful notarization produces:

```text
dist/MellowDesk-0.1.0-beta.1-macOS-universal.zip
dist/MellowDesk-0.1.0-beta.1-macOS-universal.zip.sha256
```

The script submits the archive, waits for acceptance, staples the ticket to the App, validates the staple, runs Gatekeeper assessment, recreates the archive with the stapled App, and writes the checksum.

## Final verification

Extract the exact archive into a new temporary directory and verify the distributed copy:

```bash
ditto -x -k dist/MellowDesk-0.1.0-beta.1-macOS-universal.zip /tmp/mellowdesk-release-check
codesign --verify --deep --strict --verbose=2 /tmp/mellowdesk-release-check/MellowDesk.app
xcrun stapler validate /tmp/mellowdesk-release-check/MellowDesk.app
spctl --assess --type execute --verbose=4 /tmp/mellowdesk-release-check/MellowDesk.app
lipo -info /tmp/mellowdesk-release-check/MellowDesk.app/Contents/MacOS/MellowDesk
```

The required Gatekeeper outcome is `accepted`; the executable must list both `arm64` and `x86_64`.

## GitHub Release

Create the prerelease from the tested `main` SHA, attach both files from `dist/`, and use `docs/releases/v0.1.0-beta.1.md` as the release notes. Mark beta versions as prereleases. Do not move or recreate an existing public tag.

After publishing, download the assets from GitHub and repeat the checksum, Gatekeeper, staple, and launch checks against the downloaded copy.
