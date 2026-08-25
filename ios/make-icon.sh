#!/usr/bin/env bash
#
# Builds the KeystrokeQR iOS app icon
# (Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png) from the shared brand
# master `branding/logo-master.png` (3D QR tile with the "K").
#
# iOS wants a FULL-BLEED square (no margin, no rounded corners, no alpha —
# the system applies its own mask). We crop the tile out of the master and
# scale it to 1024. The tile's own rounded corners leave black pixels in the
# extreme corners; iOS masks with a nearly identical radius, so nothing of
# that survives visually (and the tile is near-black anyway).
#
# Requires: ImageMagick 7 (`magick`).  Run: ./make-icon.sh   (from ios/)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MASTER="$HERE/../branding/logo-master.png"
OUT="$HERE/QRKeyboardScanner/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

[ -f "$MASTER" ] || { echo "Brand master not found: $MASTER" >&2; exit 1; }

# Tile crop measured on the 1254x1254 master: 1082x1082 at +85+82.
magick "$MASTER" -crop 1082x1082+85+82 +repage -resize 1024x1024 -alpha off "$OUT"

echo "iOS icon created: $OUT"
