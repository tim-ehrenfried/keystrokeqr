#!/usr/bin/env bash
#
# Erzeugt das KeystrokeQR-Host-App-Icon (Support/AppIcon.icns).
#
# Motiv (passend zum iOS-Icon): dunkler Anthrazit-Hintergrund, weißer
# QR-Viewfinder-Rahmen (vier Eck-Klammern), gelbe Scan-Linie (#FFD60A) und
# ein kleiner heller Tastatur-/Caret-Akzent (Keystroke-Hinweis).
#
# Benötigt: ImageMagick 7 (`magick`), `sips`, `iconutil` (macOS).
# Aufruf:   ./Support/make-icon.sh        (aus macos/ heraus)  oder
#           make icon
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT_ICNS="$HERE/AppIcon.icns"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

MASTER="$WORK/master.png"
GRAD="$WORK/grad.png"
BASE="$WORK/base.png"

YELLOW="#FFD60A"

# 1) Dunkler Verlauf (Anthrazit -> fast schwarz)
magick -size 1024x1024 gradient:'#212128'-'#0a0a0c' "$GRAD"

# 2) In eine abgerundete Kachel maskieren (etwas Rand ringsum)
magick "$GRAD" \
  \( -size 1024x1024 xc:black -fill white \
     -draw "roundrectangle 60,60 964,964 200,200" \) \
  -alpha off -compose CopyOpacity -composite "$BASE"

# 3) Motiv zeichnen: Scan-Linie (mit Glow), Viewfinder-Ecken, Tastenkappe + Caret
magick "$BASE" \
  -fill none \
  -stroke 'rgba(255,214,10,0.28)' -strokewidth 48 \
    -draw "stroke-linecap round line 336,486 688,486" \
  -stroke "$YELLOW" -strokewidth 26 \
    -draw "stroke-linecap round line 336,486 688,486" \
  -stroke '#FFFFFF' -strokewidth 38 \
    -draw "stroke-linecap round stroke-linejoin round polyline 288,420 288,288 420,288" \
    -draw "stroke-linecap round stroke-linejoin round polyline 604,288 736,288 736,420" \
    -draw "stroke-linecap round stroke-linejoin round polyline 736,604 736,736 604,736" \
    -draw "stroke-linecap round stroke-linejoin round polyline 420,736 288,736 288,604" \
  -stroke none -fill '#F2F2F5' \
    -draw "roundrectangle 432,522 592,682 28,28" \
  -fill none -stroke '#17171A' -strokewidth 24 \
    -draw "stroke-linecap round stroke-linejoin round polyline 474,616 512,574 550,616" \
  "$MASTER"

# 4) Iconset in allen benötigten Größen erzeugen
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
gen() { sips -z "$1" "$1" "$MASTER" --out "$ICONSET/$2" >/dev/null; }
gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png
cp "$MASTER" "$ICONSET/icon_512x512@2x.png"

# 5) In .icns wandeln
iconutil -c icns "$ICONSET" -o "$OUT_ICNS"
echo "Icon erstellt: $OUT_ICNS"
