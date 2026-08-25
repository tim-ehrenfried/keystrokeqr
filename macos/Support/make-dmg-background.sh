#!/usr/bin/env bash
#
# Erzeugt das Hintergrundbild für das KeystrokeQR-Host-DMG-Fenster.
# Dunkler Verlauf (wie das App-Icon), Titel „KeystrokeQR Host" und ein gelber
# Pfeil „→ In Programme ziehen / Drag to Applications".
#
# Ausgabe: <arg1> (PNG, 600x400 px = DMG-Fenster in Punkten).
# Benötigt: ImageMagick 7 (`magick`).
set -euo pipefail

OUT="${1:?Ausgabepfad fehlt}"
YELLOW="#FFD60A"
HERE="$(cd "$(dirname "$0")" && pwd)"
# Marken-Logo (vollflächige Kachel) aus dem Branding-Master.
LOGO_SRC="$HERE/../../branding/appstore-1024.png"

# Passende Schrift auf macOS suchen (fällt auf IM-Default zurück).
FONT_ARGS=()
for f in \
  "/System/Library/Fonts/Helvetica.ttc" \
  "/System/Library/Fonts/HelveticaNeue.ttc" \
  "/Library/Fonts/Arial.ttf"; do
  if [ -f "$f" ]; then FONT_ARGS=(-font "$f"); break; fi
done

# Logo klein und mit abgerundeten Ecken für den Kopfbereich vorbereiten.
LOGO_TMP="$(mktemp -u).png"
magick "$LOGO_SRC" -resize 56x56 \
  \( -size 56x56 xc:none -fill white -draw "roundrectangle 0,0 55,55 12,12" \) \
  -alpha off -compose CopyOpacity -composite "$LOGO_TMP"

magick -size 600x400 gradient:'#1c1c22'-'#0b0b0d' \
  "$LOGO_TMP" -gravity North -geometry +0+16 -compose over -composite \
  "${FONT_ARGS[@]}" \
  -fill '#FFFFFF' -gravity North -pointsize 28 -annotate +0+86 'KeystrokeQR Host' \
  -fill '#9A9AA2' -gravity North -pointsize 14 -annotate +0+126 'Zum Installieren das Symbol in „Programme" ziehen' \
  -fill "$YELLOW" -stroke "$YELLOW" -strokewidth 6 \
    -draw "stroke-linecap round line 250,208 348,208" \
  -stroke none -fill "$YELLOW" \
    -draw "polygon 344,192 372,208 344,224" \
  "${FONT_ARGS[@]}" \
  -fill '#9A9AA2' -stroke none -gravity North -pointsize 13 -annotate +0+338 'Drag to Applications  ·  In „Programme" ziehen' \
  "$OUT"

echo "DMG-Hintergrund erstellt: $OUT"
