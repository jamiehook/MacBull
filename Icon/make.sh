#!/bin/bash
#
# Renders the master PNG and packs all required resolutions into AppIcon.icns.
#
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Rendering master.png…"
swift make_icon.swift master.png 1024

SET="AppIcon.iconset"
rm -rf "$SET"; mkdir "$SET"

gen() { sips -z "$1" "$1" master.png --out "$SET/$2" >/dev/null; }
gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png
gen 1024 icon_512x512@2x.png

iconutil -c icns "$SET" -o AppIcon.icns
rm -rf "$SET"
echo "==> Wrote Icon/AppIcon.icns"
