#!/bin/sh
# Builds a Release app and wraps it in dist/KiteLink-<version>-macos-arm64.dmg.
#
# Ad-hoc signed by default (CI, local testing). For a public build, name a Developer ID and a notarytool keychain
# profile; the app is then signed inside-out with the hardened runtime, notarized and stapled, and so is the dmg:
#
#   KITELINK_SIGN_IDENTITY="Developer ID Application: Example Ltd (TEAMID1234)" \
#   KITELINK_NOTARY_PROFILE=EXAMPLE_NOTARY ./macos/package.sh
#
# (Create the profile once with `xcrun notarytool store-credentials`.)
set -eu
cd "$(dirname "$0")"
identity="${KITELINK_SIGN_IDENTITY:-}"
profile="${KITELINK_NOTARY_PROFILE:-}"
if [ -n "$identity" ] && [ -z "$profile" ]; then echo "KITELINK_SIGN_IDENTITY needs KITELINK_NOTARY_PROFILE" >&2; exit 1; fi

./build.sh release
app=build/KiteLink.app
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
out="../dist/KiteLink-$version-macos-arm64.dmg"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

notarize() {  # $1: a .zip or .dmg
  echo "notarizing $(basename "$1") (a few minutes)…"
  if ! xcrun notarytool submit "$1" --keychain-profile "$profile" --wait --timeout 30m > "$work/notary.log" 2>&1; then
    cat "$work/notary.log" >&2; exit 1
  fi
  if ! grep -q 'status: Accepted' "$work/notary.log"; then
    cat "$work/notary.log" >&2
    id="$(awk '/^  id: /{print $2; exit}' "$work/notary.log")"
    [ -n "$id" ] && xcrun notarytool log "$id" --keychain-profile "$profile" >&2
    exit 1
  fi
}

if [ -n "$identity" ]; then
  # Inside out: the core first, then the app around it. Neither needs entitlements.
  codesign --force --timestamp --options runtime --sign "$identity" "$app/Contents/MacOS/mihomo"
  codesign --force --timestamp --options runtime --sign "$identity" "$app"
  codesign --verify --deep --strict "$app"
  ditto -c -k --keepParent "$app" "$work/KiteLink.zip"
  notarize "$work/KiteLink.zip"
  xcrun stapler staple -q "$app"
fi

stage="$work/stage"
mkdir -p "$stage"
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
mkdir -p ../dist
rm -f "$out"
hdiutil create -quiet -volname "KiteLink $version" -srcfolder "$stage" -ov -format UDZO "$out"

if [ -n "$identity" ]; then
  codesign --force --timestamp --sign "$identity" "$out"
  notarize "$out"
  xcrun stapler staple -q "$out"
  spctl --assess --type execute "$app" && spctl --assess --type open --context context:primary-signature "$out"
  echo "notarized and stapled: app and dmg"
fi
shasum -a 256 "$out" | awk '{print $1}' > "$out.sha256"
echo "packaged $out ($(du -h "$out" | cut -f1))"
