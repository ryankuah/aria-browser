#!/bin/bash
set -euo pipefail

# Production builds must be notarized. Local-only builds are explicitly labelled
# and cannot be selected by the GitHub release workflow's asset paths.
local_only=false
if [[ "${1:-}" == "--local-only" && $# == 1 ]]; then
  local_only=true
elif [[ $# != 0 ]]; then
  echo "Usage: $0 [--local-only]" >&2
  exit 2
fi

cd "$(dirname "$0")/.."
repo_dir="$PWD"
signing_identity="${DEVELOPER_ID_APPLICATION:-Developer ID Application}"
if [[ "$local_only" == false ]]; then
  : "${NOTARY_KEYCHAIN_PROFILE:?Set NOTARY_KEYCHAIN_PROFILE to a notarytool credentials profile}"
fi

mkdir -p build/dmg
work_dir="$(mktemp -d "$repo_dir/build/dmg/run.XXXXXX")"
archive_path="$work_dir/Aria.xcarchive"
build_options=('ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO)
if [[ -n "${ARIA_VERSION:-}" ]]; then
  [[ "$ARIA_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "ARIA_VERSION must be X.Y.Z" >&2; exit 2; }
  build_options+=("MARKETING_VERSION=$ARIA_VERSION")
fi
if [[ -n "${ARIA_BUILD_NUMBER:-}" ]]; then
  [[ "$ARIA_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { echo "ARIA_BUILD_NUMBER must be a positive integer" >&2; exit 2; }
  build_options+=("CURRENT_PROJECT_VERSION=$ARIA_BUILD_NUMBER")
fi

xcodebuild archive \
  -project Browser.xcodeproj -scheme Browser -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive_path" -derivedDataPath "$work_dir/DerivedData" \
  CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$signing_identity" \
  ENABLE_APP_SANDBOX=NO ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS=--timestamp \
  "${build_options[@]}"

app_path="$archive_path/Products/Applications/Aria.app"
codesign --verify --deep --strict --verbose=2 "$app_path"
codesign -d --entitlements - --xml "$app_path" > "$work_dir/entitlements.plist"
codesign -dv --verbose=4 "$app_path" 2> "$work_dir/signature.txt"
python3 - "$app_path" "$work_dir" <<'PY'
import pathlib, plistlib, subprocess, sys
app, work = map(pathlib.Path, sys.argv[1:])
entitlements = plistlib.loads((work / "entitlements.plist").read_bytes())
for key in ("com.apple.security.app-sandbox", "com.apple.security.get-task-allow", "beta-reports-active"):
    if entitlements.get(key):
        raise SystemExit(f"Release must not contain {key}")
signature = (work / "signature.txt").read_text()
if "Authority=Developer ID Application:" not in signature or "(runtime)" not in signature or "Timestamp=" not in signature:
    raise SystemExit("Release requires Developer ID signing, hardened runtime, and a secure timestamp")
if (app / "Contents/embedded.provisionprofile").exists():
    raise SystemExit("Unexpected provisioning profile in direct-distribution app")
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
binary = app / "Contents/MacOS" / info["CFBundleExecutable"]
architectures = subprocess.check_output(["lipo", "-archs", str(binary)], text=True).split()
if set(architectures) != {"arm64", "x86_64"}:
    raise SystemExit(f"Expected a universal app, found {architectures}")
PY

notary_auth=(--keychain-profile "${NOTARY_KEYCHAIN_PROFILE:-unused}")
if [[ -n "${NOTARY_KEYCHAIN_PATH:-}" ]]; then
  notary_auth+=(--keychain "$NOTARY_KEYCHAIN_PATH")
fi
notarize() {
  local artifact="$1" report="$2" staple_target="${3:-$1}"
  if ! xcrun notarytool submit "$artifact" "${notary_auth[@]}" --wait --timeout 30m --output-format json > "$report"; then
    cat "$report"
    return 1
  fi
  python3 - "$report" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
print(f"Notarization {result.get('id')}: {result.get('status')}")
if result.get("status") != "Accepted":
    raise SystemExit("Apple did not accept this artifact; see the notarization report and notarytool log")
PY
  xcrun stapler staple "$staple_target"
  xcrun stapler validate "$staple_target"
}

if [[ "$local_only" == false ]]; then
  ditto -c -k --keepParent "$app_path" "$work_dir/Aria.zip"
  # Staple the app before packaging so it remains verifiable after drag-install.
  notarize "$work_dir/Aria.zip" "$work_dir/app-notarization.json" "$app_path"
  spctl --assess --type execute --verbose=2 "$app_path"
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
suffix=""
if [[ "$local_only" == true ]]; then suffix="-unnotarized"; fi
mkdir -p "$work_dir/staging" "$work_dir/dist"
ditto "$app_path" "$work_dir/staging/Aria.app"
ln -s /Applications "$work_dir/staging/Applications"
dmg_path="$work_dir/dist/Aria-$version-universal$suffix.dmg"
hdiutil create -volname Aria -srcfolder "$work_dir/staging" -format UDZO -fs HFS+ "$dmg_path"
codesign --force --sign "$signing_identity" --timestamp "$dmg_path"
codesign --verify --strict --verbose=2 "$dmg_path"
hdiutil verify "$dmg_path"
if [[ "$local_only" == false ]]; then
  notarize "$dmg_path" "$work_dir/dmg-notarization.json"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg_path"
fi
(cd "$work_dir/dist" && shasum -a 256 "$(basename "$dmg_path")" > SHA256SUMS.txt)
echo "DMG: $dmg_path"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "dist=$work_dir/dist" >> "$GITHUB_OUTPUT"
fi
