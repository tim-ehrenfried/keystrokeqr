#!/usr/bin/env bash
#
# Erzeugt das KeystrokeQR-iOS-App-Icon (Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png).
#
# Dasselbe Motiv wie das macOS-Icon (macos/Support/make-icon.sh) — dunkler
# Anthrazit-Verlauf, weißer QR-Viewfinder-Rahmen, gelbe Scan-Linie (#FFD60A),
# Tastenkappe + Caret — aber VOLLFLÄCHIG (kein Rand, keine abgerundeten Ecken,
# kein Alpha), da iOS die Maske/Rundung selbst anwendet. macOS ist die Referenz;
# hier wird iOS daran angeglichen.
#
# Benötigt: ImageMagick 7 (`magick`).  Aufruf: ./make-icon.sh   (aus ios/ heraus)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/QRKeyboardScanner/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
YELLOW="#FFD60A"

# Vollflächiger Verlauf (Anthrazit -> fast schwarz), identische Farben wie macOS
magick -size 1024x1024 gradient:'#212128'-'#0a0a0c' \
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
  -alpha off \
  "$OUT"

echo "iOS-Icon erstellt: $OUT"
