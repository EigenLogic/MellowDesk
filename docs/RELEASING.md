# Releasing MellowDesk

This document covers the maintainer flow for a public GitHub beta. A public binary must be reproducible from a committed SHA, signed with Developer ID and the Sparkle EdDSA key, hardened, notarized by Apple, stapled, published through the signed appcast, and tested on a real Mac.

## Release gates

Before creating a tag:

1. `./Scripts/check.sh` passes locally and CI passes on Apple Silicon and Intel runners.
2. [TEST_CHECKLIST.md](TEST_CHECKLIST.md) passes on a real MacBook.
3. `Info.plist`, `CHANGELOG.md`, and the release notes agree on the version; `MellowDeskReleaseVersion` contains the full tag version, including any Beta suffix.
4. The worktree is clean and the release commit is present on `main`.
5. The repository contains no secrets, personal history, face media, or generated build directories.
6. The Sparkle public key in `Info.plist` matches the private key stored under Keychain account `mellowdesk`.

## One-time notarization setup

Store credentials in the login Keychain. Do not put credentials in this repository, shell history, an Issue, or a GitHub Release:

```bash
xcrun notarytool store-credentials mellowdesk-notary \
  --apple-id YOUR_APPLE_ID \
  --team-id YOUR_TEAM_ID
```

The command securely prompts for an app-specific password when `--password` is omitted.

## One-time Sparkle key setup

Sparkle 2.9.5 keeps the Ed25519 private key in the login Keychain. Resolve the package, generate the organization-specific key under account `mellowdesk`, and copy only the printed public key into `SUPublicEDKey`:

```bash
swift package resolve
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account mellowdesk
```

The public key printed by this command must match `Resources/Info.plist`. The private key is a release credential: never commit it, paste it into an Issue, shell command, workflow log, or GitHub Release. Keep an encrypted offline backup outside the repository. To export that backup, choose the destination first and let the tool write it directly:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account mellowdesk \
  -x /secure/offline/location/mellowdesk-sparkle-ed25519-private-key
chmod 600 /secure/offline/location/mellowdesk-sparkle-ed25519-private-key
```

On a replacement signing Mac, import the backup with `-f` and the same `--account mellowdesk`. Do not generate a replacement key while shipped apps still trust the current public key.

## Build the public artifact

```bash
CODE_SIGN_IDENTITY="Developer ID Application: YOUR_ORGANIZATION (YOUR_TEAM_ID)" \
NOTARY_PROFILE=mellowdesk-notary \
RELEASE_VERSION=0.1.0-beta.6 \
APP_VERSION=0.1.0 \
BUILD_NUMBER=6 \
./Scripts/package_release.sh
```

The script enforces a Developer ID signature and arm64 + x86_64 universal builds for the main executable and Sparkle framework. It signs Sparkle's nested helpers, including `Installer.xpc`, before the framework and main App, then verifies the sandbox Mach-service entitlements. Without `NOTARY_PROFILE`, it fails closed. `ALLOW_UNNOTARIZED=1` is only for a local test candidate and must never be used for a public Release.

Successful notarization produces:

```text
dist/MellowDesk-0.1.0-beta.6-macOS-universal.zip
dist/MellowDesk-0.1.0-beta.6-macOS-universal.zip.sha256
```

The script submits the archive, waits for acceptance, staples the ticket to the App, validates the staple, runs Gatekeeper assessment, recreates the archive with the stapled App, and writes the checksum.

## Final verification

Extract the exact archive into a new temporary directory and verify the distributed copy:

```bash
ditto -x -k dist/MellowDesk-0.1.0-beta.6-macOS-universal.zip /tmp/mellowdesk-release-check
codesign --verify --deep --strict --verbose=2 /tmp/mellowdesk-release-check/MellowDesk.app
xcrun stapler validate /tmp/mellowdesk-release-check/MellowDesk.app
spctl --assess --type execute --verbose=4 /tmp/mellowdesk-release-check/MellowDesk.app
lipo -info /tmp/mellowdesk-release-check/MellowDesk.app/Contents/MacOS/MellowDesk
```

The required Gatekeeper outcome is `accepted`; the main executable and Sparkle framework must list both `arm64` and `x86_64`. Verify the nested Installer signature as well:

```bash
codesign --verify --strict --verbose=2 \
  /tmp/mellowdesk-release-check/MellowDesk.app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc
```

Also verify that `MellowDeskReleaseVersion` exactly matches the tag, `CFBundleVersion` is greater than every published build, `SUFeedURL` points to the raw GitHub `main` appcast, and the automatic-update, signed-feed, pre-extraction-verification, Installer launcher, and no-system-profiling keys have their expected values.

## Publish the archive, then the appcast

The GitHub Release asset must exist before its appcast entry can be generated. Use this order:

1. Confirm `origin/main` is the exact tested source SHA and the intended tag does not already exist.
2. Create the immutable GitHub prerelease tag from that SHA, attach the ZIP and SHA-256 file from `dist/`, and use `docs/releases/v0.1.0-beta.6.md` as the release notes. Mark beta versions as prereleases. Never move or recreate a public tag.
3. Download both assets from GitHub and repeat checksum, Gatekeeper, staple, nested-signature, architecture, version, and launch checks against the downloaded copy.
4. Generate the appcast entry from that exact archive. The script reads the EdDSA key from Keychain account `mellowdesk`, embeds release notes, signs the update and feed, and refuses a missing archive, checksum, release note, signature, build number, or final GitHub download URL:

```bash
SPARKLE_KEY_ACCOUNT=mellowdesk \
RELEASE_VERSION=0.1.0-beta.6 \
BUILD_NUMBER=6 \
./Scripts/generate_appcast.sh
```

5. Inspect `appcast.xml` without hand-editing it. Confirm the new item uses the exact immutable GitHub Release ZIP URL, expected build number and display version, minimum macOS version, EdDSA signature, and signed-feed metadata.
6. Commit only the intended feed change on a branch, open a non-draft Ready PR, wait for all required CI and review gates, and merge it. This second PR activates the release for installed apps through `https://raw.githubusercontent.com/EigenLogic/MellowDesk/main/appcast.xml`.
7. Fetch the raw `main` appcast and confirm it is the merged signed file, then complete the old-build-to-new-build acceptance below. Do not call the release complete until that pass succeeds.

## End-to-end updater acceptance

For every release after beta.4, start with the previous public Sparkle-enabled build installed in `/Applications`. Record a few settings and history entries, keep automatic updates enabled, and use **Check Now** to make the test deterministic. Confirm the old build reads the production appcast, downloads the new GitHub Release ZIP in the background while the rest of the app remains usable, performs EdDSA and Developer ID verification, and shows the in-app ready prompt without opening a browser.

Test both choices across the release candidate or QA cycles:

- **Install and Relaunch:** the old process exits, the verified App is replaced, MellowDesk relaunches on the new build, and prior settings and history remain readable.
- **Later:** the ready prompt closes, no browser opens, and quitting MellowDesk installs the downloaded update; the next launch reports the new build with prior settings and history intact.

Beta.4 is the first Sparkle seed, so beta.3 cannot perform this updater flow. Beta.3 to beta.4 is the final manual download and installation. For beta.4, verify the Sparkle framework, signed-feed configuration, Installer service, automatic-update default, and manual check in the installed notarized App; the full production old-build-to-new-build gate becomes mandatory starting with the next release.
