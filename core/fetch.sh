#!/bin/sh
# Fetches the pinned mihomo core and the geo databases it needs into a build directory.
#   core/fetch.sh darwin-arm64 macos/build/core
# mihomo is verified against core/mihomo.version (sha256 of the unpacked binary). The geo files come from
# MetaCubeX/meta-rules-dat's rolling "latest" release and are refreshed when older than a day.
set -eu
platform="${1:-darwin-arm64}"
out="${2:-macos/build/core}"
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$out"

line="$(grep -v '^#' "$here/mihomo.version" | grep "mihomo-$platform-" | head -1)"
[ -n "$line" ] || { echo "no pinned mihomo for $platform" >&2; exit 1; }
tag="$(echo "$line" | awk '{print $1}')"
asset="$(echo "$line" | awk '{print $2}')"
sha="$(echo "$line" | awk '{print $3}')"

have="$( [ -f "$out/mihomo" ] && shasum -a 256 "$out/mihomo" | awk '{print $1}' || true )"
if [ "$have" != "$sha" ]; then
  echo "fetching mihomo $tag ($asset)"
  curl -fsSL --retry 3 -o "$out/mihomo.gz" "https://github.com/MetaCubeX/mihomo/releases/download/$tag/$asset"
  gunzip -f "$out/mihomo.gz"
  chmod +x "$out/mihomo"
  got="$(shasum -a 256 "$out/mihomo" | awk '{print $1}')"
  [ "$got" = "$sha" ] || { echo "sha256 mismatch for mihomo: $got" >&2; rm -f "$out/mihomo"; exit 1; }
fi
"$out/mihomo" -v | head -1

for f in geoip.metadb geosite.dat country.mmdb; do
  if [ -z "$(find "$out/$f" -mtime -1 2>/dev/null)" ]; then
    echo "fetching $f"
    curl -fsSL --retry 3 -o "$out/$f" "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/$f"
  fi
done
ls -la "$out"
