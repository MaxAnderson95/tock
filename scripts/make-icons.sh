#!/bin/bash
# Renders assets/Tock.icns and assets/png/tock-icon-256.png from assets/tock-icon.svg (Apple's 1024 grid: 824 tile, 100 margin) with AppKit's SVG renderer.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d "${TMPDIR:-/tmp}/tock-icons.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

iconset="$tmp/Tock.iconset"
mkdir -p "$iconset"
for point in 16 32 128 256 512; do
    swift scripts/render-svg.swift assets/tock-icon.svg "$iconset/icon_${point}x${point}.png" "$point"
    swift scripts/render-svg.swift assets/tock-icon.svg "$iconset/icon_${point}x${point}@2x.png" "$((point * 2))"
done
iconutil -c icns "$iconset" -o assets/Tock.icns

# The README shows the icon from this PNG.
mkdir -p assets/png
cp "$iconset/icon_128x128@2x.png" assets/png/tock-icon-256.png
