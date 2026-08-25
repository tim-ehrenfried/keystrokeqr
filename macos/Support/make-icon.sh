#!/usr/bin/env bash
#
# Builds the KeystrokeQR Host app icon (Support/AppIcon.icns) from the shared
# brand master `branding/logo-master.png` (3D QR tile with the "K").
#
# Pipeline: crop the tile out of the master (it sits on a pure-black canvas),
# apply a rounded-rect alpha mask (slightly tighter than the rendered corner
# radius, so no black fringes survive), add a soft drop shadow, and center the
# 824 px tile on a transparent 1024 canvas (Apple's standard margin). Then emit
# the full iconset via sips + iconutil.
#
# Requires: ImageMagick 7 (`magick`), `sips`, `iconutil` (macOS).
# Run:      ./Support/make-icon.sh   (from macos/)   or   make icon
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MASTER="$HERE/../../branding/logo-master.png"
OUT_ICNS="$HERE/AppIcon.icns"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -f "$MASTER" ] || { echo "Brand master not found: $MASTER" >&2; exit 1; }

# 1) Crop the tile (measured on the 1254x1254 master: 1082x1082 at +85+82).
magick "$MASTER" -crop 1082x1082+85+82 +repage "$WORK/tile.png"

# 2) Rounded-rect mask + shadow, centered on transparent 1024.
magick "$WORK/tile.png" -resize 824x824 \
  \( -size 824x824 xc:none -fill white -draw "roundrectangle 0,0 823,823 180,180" \) \
  -alpha off -compose CopyOpacity -composite "$WORK/tile-masked.png"
magick "$WORK/tile-masked.png" \
  \( +clone -background black -shadow 35x14+0+10 \) +swap \
  -background none -layers merge +repage \
  -gravity center -background none -extent 1024x1024 "$WORK/master1024.png"

# 3) Iconset in all required sizes.
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" "$WORK/master1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z "$d" "$d" "$WORK/master1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done

# 4) Convert to .icns.
iconutil -c icns "$ICONSET" -o "$OUT_ICNS"
echo "Icon created: $OUT_ICNS"
