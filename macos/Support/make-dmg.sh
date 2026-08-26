#!/usr/bin/env bash
#
# Baut ein gestyltes DMG aus dem fertigen .app-Bundle.
#
#   make-dmg.sh <APP_BUNDLE> <VOLNAME> <OUT_DMG> <BG_PNG> [SIGN_IDENTITY]
#
# Fenster mit Hintergrundbild, App-Icon links, /Applications-Symlink rechts,
# gesetzte Icon-Positionen + Fenstergröße.
#
# Bevorzugt `create-dmg` (Homebrew), sonst robuster `hdiutil`-Pfad. Das
# Feinstyling (Icon-Positionen/Hintergrund über Finder-AppleScript) benötigt
# eine GUI-/Finder-Session; im Headless-/CI-Kontext ist es best-effort — das
# DMG enthält dann trotzdem das App-Bundle, den /Applications-Symlink und das
# Hintergrundbild im Volume (.background/background.png), nur ohne die
# vorgesetzten Icon-Koordinaten (siehe README, „Einschränkung").
set -euo pipefail

APP_BUNDLE="${1:?App-Bundle fehlt}"
VOLNAME="${2:?Volume-Name fehlt}"
OUT_DMG="${3:?Ausgabe-DMG fehlt}"
BG_PNG="${4:?Hintergrundbild fehlt}"
SIGN_IDENTITY="${5:--}"
# Optional: Volume-Icon (.icns) — macht Volume & DMG-Datei zum Marken-Icon.
VOL_ICNS="${6:-}"

APP_BASENAME="$(basename "$APP_BUNDLE")"
WIN_W=600; WIN_H=400
ICON_SIZE=110
APP_X=150;  APP_Y=205
APPS_X=450; APPS_Y=205

# Secure Timestamp: von Apple für Developer-ID-Signaturen verlangt
# (Notarisierung scheitert sonst); bei ad-hoc ("-") wird Timestamping nicht
# unterstützt (codesign würde fehlschlagen) — daher nur setzen, wenn eine
# echte Signing-Identität übergeben wurde. Bewusst ein einfacher String statt
# eines Arrays: macOS' /bin/bash ist 3.2, das "${ARR[@]}" bei leerem Array
# unter `set -u` fälschlich als unbound variable ablehnt.
TIMESTAMP_FLAG=""
if [ "$SIGN_IDENTITY" != "-" ]; then
  TIMESTAMP_FLAG="--timestamp"
fi

rm -f "$OUT_DMG"

# ---- Bevorzugt: dmgbuild (headless-fähig, kein Finder/AppleScript) ---------
# Schreibt die .DS_Store (Hintergrund, Icon-Positionen, Fenstergröße)
# programmatisch — funktioniert deterministisch auch auf CI-Runnern.
HERE="$(cd "$(dirname "$0")" && pwd)"
if python3 -c "import dmgbuild" >/dev/null 2>&1; then
  echo "make-dmg: nutze dmgbuild"
  python3 -m dmgbuild -s "$HERE/dmgbuild-settings.py" \
    -D app="$APP_BUNDLE" \
    -D background="$BG_PNG" \
    ${VOL_ICNS:+-D icns="$VOL_ICNS"} \
    "$VOLNAME" "$OUT_DMG"
  codesign --force $TIMESTAMP_FLAG --sign "$SIGN_IDENTITY" "$OUT_DMG" 2>/dev/null && \
    echo "make-dmg: DMG signiert ($SIGN_IDENTITY)" || \
    echo "make-dmg: DMG-Signatur übersprungen"
  echo "make-dmg: erstellt $OUT_DMG (gestylt via dmgbuild)"
  exit 0
fi

# ---- Fallback: create-dmg -------------------------------------------------
if command -v create-dmg >/dev/null 2>&1; then
  echo "make-dmg: nutze create-dmg"
  VOLICON_ARGS=()
  [ -n "$VOL_ICNS" ] && [ -f "$VOL_ICNS" ] && VOLICON_ARGS=(--volicon "$VOL_ICNS")
  create-dmg \
    --volname "$VOLNAME" \
    --background "$BG_PNG" \
    "${VOLICON_ARGS[@]}" \
    --window-pos 200 120 \
    --window-size "$WIN_W" "$WIN_H" \
    --icon-size "$ICON_SIZE" \
    --icon "$APP_BASENAME" "$APP_X" "$APP_Y" \
    --app-drop-link "$APPS_X" "$APPS_Y" \
    --no-internet-enable \
    "$OUT_DMG" "$APP_BUNDLE"
  if [ "$SIGN_IDENTITY" != "-" ] || true; then
    codesign --force $TIMESTAMP_FLAG --sign "$SIGN_IDENTITY" "$OUT_DMG" 2>/dev/null || \
      echo "make-dmg: DMG-Signatur übersprungen"
  fi
  echo "make-dmg: erstellt $OUT_DMG"
  exit 0
fi

# ---- Fallback: hdiutil ----------------------------------------------------
echo "make-dmg: create-dmg nicht gefunden – nutze hdiutil"
STAGE="$(mktemp -d)"
RW_DMG="$(mktemp -u).dmg"
MOUNT_DIR=""
cleanup() {
  [ -n "$MOUNT_DIR" ] && hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true
  rm -rf "$STAGE"; rm -f "$RW_DMG"
}
trap cleanup EXIT

# Staging-Inhalt: App + /Applications-Symlink + verstecktes Hintergrundbild
cp -R "$APP_BUNDLE" "$STAGE/$APP_BASENAME"
ln -s /Applications "$STAGE/Applications"
mkdir "$STAGE/.background"
cp "$BG_PNG" "$STAGE/.background/background.png"
# Volume-Icon (best-effort): .VolumeIcon.icns + Custom-Icon-Attribut aufs Volume.
if [ -n "$VOL_ICNS" ] && [ -f "$VOL_ICNS" ]; then
  cp "$VOL_ICNS" "$STAGE/.VolumeIcon.icns"
fi

# Beschreibbares DMG erzeugen (etwas Puffer über der Nutzgröße)
hdiutil create -srcfolder "$STAGE" -volname "$VOLNAME" \
  -fs HFS+ -format UDRW -ov "$RW_DMG" -quiet

# Mounten — bewusst OHNE -nobrowse und OHNE eigenen Mountpoint: nur für
# regulär unter /Volumes gemountete, browsebare Volumes schreibt der Finder
# die .DS_Store (Fensterlayout/Hintergrund). Das Volume erscheint dadurch
# während des Builds kurz im Finder — das ist der Preis fürs Styling.
hdiutil attach "$RW_DMG" -noverify -noautoopen -quiet
MOUNT_DIR="/Volumes/$VOLNAME"
if [ ! -d "$MOUNT_DIR" ]; then
  echo "make-dmg: WARNUNG – erwarteter Mountpoint $MOUNT_DIR fehlt" >&2
  MOUNT_DIR="$(hdiutil info | grep -A1 "$RW_DMG" | grep '/Volumes/' | awk '{print $NF}' | head -1)"
fi

# Best-effort Feinstyling über Finder-AppleScript (in Headless/CI oft nicht
# erlaubt → Fehler werden ignoriert, das DMG bleibt trotzdem gültig).
if osascript >/dev/null 2>&1 <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, $((200 + WIN_W)), $((120 + WIN_H))}
    set theView to the icon view options of container window
    set arrangement of theView to not arranged
    set icon size of theView to $ICON_SIZE
    set background picture of theView to file ".background:background.png"
    set position of item "$APP_BASENAME" of container window to {$APP_X, $APP_Y}
    set position of item "Applications" of container window to {$APPS_X, $APPS_Y}
    update without registering applications
    close
  end tell
end tell
APPLESCRIPT
then
  echo "make-dmg: Finder-Styling angewendet"
  # Der Finder schreibt die .DS_Store (Fensterlayout + Hintergrund) VERZÖGERT —
  # ohne Wartezeit fehlt sie im finalen DMG und das Styling geht verloren.
  sync
  for i in 1 2 3 4 5 6 7 8 9 10; do
    [ -f "$MOUNT_DIR/.DS_Store" ] && break
    sleep 1
  done
  sleep 2
  sync
  if [ -f "$MOUNT_DIR/.DS_Store" ]; then
    echo "make-dmg: .DS_Store geschrieben"
  else
    echo "make-dmg: WARNUNG – .DS_Store wurde nicht geschrieben (Styling geht verloren)"
  fi
else
  echo "make-dmg: Finder-Styling nicht möglich (Headless/CI) – DMG enthält App, /Applications-Symlink und Hintergrundbild, aber keine vorgesetzten Icon-Positionen."
fi

# Custom-Icon-Flag fürs Volume setzen (SetFile kommt mit den Xcode-Tools;
# ohne das Flag ignoriert der Finder .VolumeIcon.icns). Best-effort.
if [ -n "$VOL_ICNS" ] && [ -f "$MOUNT_DIR/.VolumeIcon.icns" ]; then
  if command -v SetFile >/dev/null 2>&1; then
    SetFile -a C "$MOUNT_DIR" 2>/dev/null && echo "make-dmg: Volume-Icon gesetzt" || true
  else
    echo "make-dmg: SetFile nicht verfügbar – Volume-Icon-Flag übersprungen"
  fi
fi

hdiutil detach "$MOUNT_DIR" -quiet
MOUNT_DIR=""

# In komprimiertes, schreibgeschütztes DMG wandeln
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUT_DMG" -ov -quiet

# Optional signieren (ad-hoc "-" oder Developer-ID)
codesign --force $TIMESTAMP_FLAG --sign "$SIGN_IDENTITY" "$OUT_DMG" 2>/dev/null && \
  echo "make-dmg: DMG signiert ($SIGN_IDENTITY)" || \
  echo "make-dmg: DMG-Signatur übersprungen"

echo "make-dmg: erstellt $OUT_DMG"
