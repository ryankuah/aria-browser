# Aria

A SwiftUI/WebKit browser for macOS.

## Download and install

Download the latest DMG from [GitHub Releases](https://github.com/ryankuah/browser/releases), open it, and drag Aria into Applications. New releases from this pipeline support both Apple Silicon and Intel Macs on macOS 15 or later. Historical releases predate this pipeline; use a release whose notes confirm Developer ID signing and notarization.

Aria now uses direct distribution with Developer ID signing, hardened runtime, and Apple notarization. App Sandbox is disabled; camera and microphone access still require permission. Download quarantine is separate from App Sandbox: the existing **Remove Download Quarantine** setting still controls Aria's attempt to remove that attribute from completed downloads.

Updates are installed from GitHub Releases. There is no automatic updater, and TestFlight does not update the direct build.

## Release through GitHub

The `Release DMG` workflow in `.github/workflows/release-dmg.yml` builds a universal app, checks its signature and entitlements, notarizes and staples the app, packages a drag-to-Applications DMG, then signs, notarizes, staples, and verifies the DMG. Only after all checks pass does it publish the DMG and `SHA256SUMS.txt` to a GitHub Release. It does not upload to App Store Connect or TestFlight.

Configure these repository **Actions secrets** once:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Base64-encoded Developer ID Application certificate **and private key**, exported as a password-protected `.p12` for team `8H8H5W877U`. An Apple Development or App Store certificate cannot replace this. |
| `DEVELOPER_ID_P12_PASSWORD` | Password for that `.p12` export. |
| `APPLE_ID` | Apple developer account email with access to team `8H8H5W877U`. |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for Apple's notarization service. |

For example, upload the certificate without printing it:

```sh
base64 -i /path/to/DeveloperID.p12 | gh secret set DEVELOPER_ID_P12_BASE64
gh secret set DEVELOPER_ID_P12_PASSWORD
gh secret set APPLE_ID
gh secret set APPLE_APP_SPECIFIC_PASSWORD
```

Keep credentials out of Git. The workflow imports them into a temporary keychain and deletes it after the job. GitHub's provided token publishes the release; no personal access token is needed.

Commit and push the intended release source, then push a new `vX.Y.Z` tag, for example:

```sh
git tag v1.5.3
git push origin v1.5.3
```

The tag sets the app's marketing version; the workflow run number sets its build number. You can also run `Release DMG` manually with an existing version tag containing this pipeline. Existing GitHub releases are never overwritten; retry a failed job before publication or use a new version tag. Pushing normal commits does not publish a release.

## Build a DMG locally

Use Xcode 26 or newer and a Developer ID Application identity in your keychain. Store notarization credentials interactively, then run:

```sh
xcrun notarytool store-credentials aria-notary
NOTARY_KEYCHAIN_PROFILE=aria-notary bash scripts/build-dmg.sh
```

Outputs are saved in a unique `build/dmg/run.*/dist/` directory. Optional environment variables are `ARIA_VERSION`, `ARIA_BUILD_NUMBER`, `DEVELOPER_ID_APPLICATION` (certificate name or hash), and `NOTARY_KEYCHAIN_PATH` (for a nondefault keychain).

For local packaging checks without notarization credentials, use `bash scripts/build-dmg.sh --local-only`. This still requires Developer ID signing and produces a clearly labelled `-unnotarized.dmg` for testing, not publication. The GitHub workflow always requires notarization.

## Switching from TestFlight

Quit Aria before replacing the TestFlight copy in Applications. The bundle ID remains `com.ryankuah.browser`, but leaving App Sandbox changes the default data locations. Existing data is preserved in the old container; this change does not automatically migrate it.

To transfer tabs, history, bookmarks, and userscripts manually, with **both copies quit**, back up the old `~/Library/Containers/com.ryankuah.browser/Data/Library/Application Support/com.ryankuah.browser/` folder, then copy it to `~/Library/Application Support/com.ryankuah.browser/` before launching the direct build for the first time. Copy the entire folder, including any SQLite sidecar files. If a destination already exists, back it up and choose which profile to keep instead of merging databases. macOS may request permission to read the old container.

Settings and WebKit website data are separate from that folder and are not migrated by this copy; recheck settings and sign in to websites again as needed. The direct build stores new passwords in the macOS login keychain under Aria's own security domain. Passwords from TestFlight's Data Protection Keychain are left intact but must be entered and saved again in the direct build, including when you copy the old database. TestFlight/App Store builds require a sandboxed configuration and are no longer the release path in this repository.

## Backlog

- Merge pending media permission toasts for the same origin. If a site requests camera and then requests microphone while the first permission toast is still pending, update the existing toast to "Camera and Microphone" instead of showing a second toast. Store both WebKit decision handlers on the same pending request and resolve them together when the user chooses Allow or Deny.
