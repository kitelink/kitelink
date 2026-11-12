#!/bin/sh
# Builds a Release app and wraps it in dist/KiteLink-<version>-macos-arm64.dmg (ad-hoc signed).
set -eu
cd "$(dirname "$0")"
./build.sh release
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/KiteLink.app/Contents/Info.plist)"
out="../dist/KiteLink-$version-macos-arm64.dmg"
stage="$(mktemp -d)"
cp -R build/KiteLink.app "$stage/"
ln -s /Applications "$stage/Applications"
mkdir -p ../dist
rm -f "$out"
hdiutil create -quiet -volname "KiteLink $version" -srcfolder "$stage" -ov -format UDZO "$out"
rm -rf "$stage"
echo "packaged $out ($(du -h "$out" | cut -f1))"
