#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
case "$configuration" in debug|release) ;; *) echo 'Usage: scripts/build-app.sh [debug|release]' >&2; exit 2;; esac
swift build -c "$configuration"
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app_dir="$PWD/dist/MediaInfo QuickLook.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/MediaInfoQuickLook" "$app_dir/Contents/MacOS/MediaInfoQuickLook.new"
mv -f "$app_dir/Contents/MacOS/MediaInfoQuickLook.new" "$app_dir/Contents/MacOS/MediaInfoQuickLook"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
# Local ad-hoc signature; Developer ID + notarization are separate release steps.
codesign --force --sign "${CODE_SIGN_IDENTITY:--}" --options runtime --entitlements Resources/MediaInfoQuickLook.entitlements "$app_dir"
codesign --verify --deep --strict "$app_dir"
/usr/bin/ditto -c -k --keepParent "$app_dir" "$PWD/dist/MediaInfo-QuickLook-macOS.zip"
echo "$app_dir"
