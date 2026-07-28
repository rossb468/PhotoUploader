#!/bin/bash
# Builds PhotoUploader.app — a real, double-clickable macOS app bundle — and
# drops it in the repo root. Convenience wrapper around the Xcode project;
# building in Xcode directly does the same thing.
#
# The bundle's Info.plist comes from project.yml (via the generated Xcode
# project), so this script deliberately does NOT hand-roll one — that used to
# be a second source of truth and the two had already drifted apart.
set -euo pipefail
cd "$(dirname "$0")"

# Keep the project in sync with project.yml when xcodegen is available, so
# newly added source files don't silently go missing from the build.
if command -v xcodegen >/dev/null 2>&1; then
    echo "Regenerating Xcode project from project.yml…"
    xcodegen generate --quiet
fi

echo "Building (Release)…"
xcodebuild \
    -project PhotoUploader.xcodeproj \
    -scheme PhotoUploader \
    -configuration Release \
    -derivedDataPath .build/xcode \
    build

APP="PhotoUploader.app"
rm -rf "$APP"
# ditto (rather than cp -R) copies the bundle without dragging along the
# Finder metadata that makes codesign refuse to sign it.
ditto ".build/xcode/Build/Products/Release/$APP" "$APP"

# Belt and braces: strip any remaining extended attributes, since a stray
# com.apple.FinderInfo is enough to fail signing with "resource fork, Finder
# information, or similar detritus not allowed".
xattr -cr "$APP"

# Xcode only applies a lightweight linker signature (Info.plist unbound,
# resources unsealed). Re-sign ad-hoc so the bundle is properly sealed and
# behaves when moved to /Applications.
codesign --force --deep --sign - "$APP"

echo "Built $APP"
