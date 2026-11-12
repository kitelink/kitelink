#!/bin/sh
# Builds KiteLink.app into macos/build/KiteLink.app (Debug by default; `./build.sh release` for Release).
#   needs: Xcode, xcodegen (brew install xcodegen)
set -eu
cd "$(dirname "$0")"
config="Debug"; [ "${1:-}" = "release" ] && config="Release"
xcodegen generate --quiet
mkdir -p build
if ! xcodebuild -project KiteLink.xcodeproj -scheme KiteLink -configuration "$config" -derivedDataPath build/DerivedData \
  -destination 'platform=macOS,arch=arm64' build > build/xcodebuild.log 2>&1; then
  grep -E 'error:|BUILD FAILED' build/xcodebuild.log | sort -u >&2 || true
  echo "build failed; full log in macos/build/xcodebuild.log" >&2
  exit 1
fi
rm -rf build/KiteLink.app
cp -R "build/DerivedData/Build/Products/$config/KiteLink.app" build/KiteLink.app
echo "built macos/build/KiteLink.app ($config)"
