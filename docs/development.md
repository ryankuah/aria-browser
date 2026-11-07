# Development and releases

## Build

Open `Browser.xcodeproj` in Xcode 26 or newer and run the `Browser` scheme. Select your development signing team if needed.

## Release

`build-dmg.sh` is the only DMG build path. It builds a universal app, signs with Developer ID and hardened runtime, notarizes and staples the app and DMG, and generates `SHA256SUMS.txt`.

The installer uses a 600 × 400 Finder window with a custom cyan/lavender background and fixed drag-to-Applications layout. Packaging requires Python 3.10 or newer; the script installs pinned packaging dependencies in its temporary build directory.

Install a Developer ID Application certificate with its private key in your keychain. Store your notarization credentials once:

```sh
xcrun notarytool store-credentials aria-notary
```

Set the version and build number in Xcode, then run:

```sh
NOTARY_KEYCHAIN_PROFILE=aria-notary ./build-dmg.sh
```

The script prints the DMG path under `build/dmg/run.*/dist/`. Create a GitHub Release with a `vX.Y.Z` tag at the matching source commit and attach the DMG and `SHA256SUMS.txt` from that directory.

Optional environment variables: `ARIA_VERSION`, `ARIA_BUILD_NUMBER`, `DEVELOPER_ID_APPLICATION` (certificate name or hash), and `NOTARY_KEYCHAIN_PATH` (for a nondefault keychain).
