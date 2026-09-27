# Aria

A SwiftUI/WebKit browser for macOS.

## App Store Release

This app is configured for Mac App Store distribution.

Before submitting, confirm the App Store Connect app record and bundle ID are set up for:

- Bundle ID: `com.ryankuah.browser`
- App Sandbox enabled through `Browser/Browser.entitlements`
- App Store signing in Xcode
- Privacy, age rating, export compliance, screenshots, and review metadata in App Store Connect

Create and upload an App Store archive from Xcode with Product > Archive, then Distribute App > App Store Connect. From the command line, create an archive with:

```sh
xcodebuild \
  -project Browser.xcodeproj \
  -scheme Browser \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  archive
```

Non-App-Store distribution packaging is intentionally not part of this repo path.

## Backlog

- Merge pending media permission toasts for the same origin. If a site requests camera and then requests microphone while the first permission toast is still pending, update the existing toast to "Camera and Microphone" instead of showing a second toast. Store both WebKit decision handlers on the same pending request and resolve them together when the user chooses Allow or Deny.
