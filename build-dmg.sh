#!/bin/bash
set -euo pipefail

if [[ $# != 0 ]]; then
  echo "Usage: $0" >&2
  exit 2
fi

cd "$(dirname "$0")"
repo_dir="$PWD"
signing_identity="${DEVELOPER_ID_APPLICATION:-Developer ID Application}"
: "${NOTARY_KEYCHAIN_PROFILE:?Set NOTARY_KEYCHAIN_PROFILE to a notarytool credentials profile}"

mkdir -p build/dmg
work_dir="$(mktemp -d "$repo_dir/build/dmg/run.XXXXXX")"
# Keep packaging dependencies isolated from the system Python.
python3 -m venv "$work_dir/tools"
"$work_dir/tools/bin/python" -m pip install --disable-pip-version-check \
  'dmgbuild==1.6.7' 'ds-store==1.3.3' 'mac-alias==2.2.3'
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

notary_auth=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
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

ditto -c -k --keepParent "$app_path" "$work_dir/Aria.zip"
# Staple the app before packaging so it remains verifiable after drag-install.
notarize "$work_dir/Aria.zip" "$work_dir/app-notarization.json" "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
mkdir -p "$work_dir/dist"
dmg_path="$work_dir/dist/Aria-$version-universal.dmg"

# Render both standard and Retina representations at the same logical size.
# This is installer artwork, not a resource bundled into the app.
xcrun swift -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "$work_dir/ModuleCache" - "$work_dir" <<'SWIFT'
import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 600, height: 400)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
        pixelsWide: 600 * scale, pixelsHigh: 400 * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    NSGradient(colors: [color(0.82, 0.94, 0.98), color(0.91, 0.88, 0.98)])!
        .draw(in: NSRect(origin: .zero, size: size), angle: -35)

    let wave = NSBezierPath()
    wave.move(to: NSPoint(x: 0, y: 0))
    wave.line(to: NSPoint(x: 600, y: 0))
    wave.line(to: NSPoint(x: 600, y: 125))
    wave.curve(to: NSPoint(x: 0, y: 55),
        controlPoint1: NSPoint(x: 365, y: 200), controlPoint2: NSPoint(x: 220, y: -25))
    wave.close()
    color(1, 1, 1, 0.24).setFill()
    wave.fill()

    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 276, y: 220))
    arrow.line(to: NSPoint(x: 324, y: 220))
    arrow.move(to: NSPoint(x: 314, y: 230))
    arrow.line(to: NSPoint(x: 324, y: 220))
    arrow.line(to: NSPoint(x: 314, y: 210))
    arrow.lineWidth = 2.5
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    color(0.32, 0.36, 0.57, 0.65).setStroke()
    arrow.stroke()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    ("Drag Aria to Applications" as NSString).draw(
        in: NSRect(x: 60, y: 85, width: 480, height: 24),
        withAttributes: [.font: NSFont.systemFont(ofSize: 15, weight: .medium),
                         .foregroundColor: color(0.28, 0.31, 0.46),
                         .paragraphStyle: paragraph])

    NSGraphicsContext.restoreGraphicsState()
    let name = scale == 1 ? "background.tiff" : "background@2x.tiff"
    try bitmap.representation(using: .tiff, properties: [:])!
        .write(to: directory.appendingPathComponent(name))
}
SWIFT

# Write Finder metadata without scripting Finder or inheriting local view settings.
"$work_dir/tools/bin/python" - "$app_path" "$dmg_path" "$work_dir" <<'PY'
import pathlib, sys
from dmgbuild import build_dmg

app, output, work = map(pathlib.Path, sys.argv[1:])
build_dmg(str(output), "Aria", settings={
    "format": "UDZO",
    "filesystem": "HFS+",
    "files": [str(app)],
    "symlinks": {"Applications": "/Applications"},
    "background": str(work / "background.tiff"),
    "window_rect": ((200, 200), (600, 400)),
    "default_view": "icon-view",
    "show_toolbar": False,
    "show_sidebar": False,
    "show_status_bar": False,
    "show_pathbar": False,
    "show_tab_view": False,
    "arrange_by": None,
    "grid_spacing": 80,
    "scroll_position": (0, 0),
    "icon_size": 96,
    "text_size": 13,
    "icon_locations": {"Aria.app": (160, 180), "Applications": (440, 180)},
})
PY

# Verify the packaged copy too: Finder flags can invalidate an otherwise valid app.
python3 - "$dmg_path" <<'PY'
import pathlib, plistlib, subprocess, sys

mounted = plistlib.loads(subprocess.check_output([
    "hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen", "-plist", sys.argv[1]
]))
volume = next(item for item in mounted["system-entities"] if "mount-point" in item)
try:
    app = pathlib.Path(volume["mount-point"]) / "Aria.app"
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    subprocess.run(["xcrun", "stapler", "validate", str(app)], check=True)
    subprocess.run(["spctl", "--assess", "--type", "execute", "--verbose=2", str(app)], check=True)
finally:
    subprocess.run(["hdiutil", "detach", volume["dev-entry"]], check=True)
PY

codesign --force --sign "$signing_identity" --timestamp "$dmg_path"
codesign --verify --strict --verbose=2 "$dmg_path"
hdiutil verify "$dmg_path"
notarize "$dmg_path" "$work_dir/dmg-notarization.json"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg_path"
(cd "$work_dir/dist" && shasum -a 256 "$(basename "$dmg_path")" > SHA256SUMS.txt)
echo "DMG: $dmg_path"
