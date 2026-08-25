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

APP_BASENAME="$(basename "$APP_BUNDLE")"
WIN_W=600; WIN_H=400
ICON_SIZE=110
APP_X=150;  APP_Y=205
APPS_X=450; APPS_Y=205

rm -f "$OUT_DMG"

# ---- Bevorzugt: create-dmg ------------------------------------------------
if command -v create-dmg >/dev/null 2>&1; then
  echo "make-dmg: nutze create-dmg"
  create-dmg \
    --volname "$VOLNAME" \
    --background "$BG_PNG" \
    --window-pos 200 120 \
    --window-size "$WIN_W" "$WIN_H" \
    --icon-size "$ICON_SIZE" \
    --icon "$APP_BASENAME" "$APP_X" "$APP_Y" \
    --app-drop-link "$APPS_X" "$APPS_Y" \
    --no-internet-enable \
    "$OUT_DMG" "$APP_BUNDLE"
  if [ "$SIGN_IDENTITY" != "-" ] || true; then
    codesign --force --sign "$SIGN_IDENTITY" "$OUT_DMG" 2>/dev/null || \
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

# Beschreibbares DMG erzeugen (etwas Puffer über der Nutzgröße)
hdiutil create -srcfolder "$STAGE" -volname "$VOLNAME" \
  -fs HFS+ -format UDRW -ov "$RW_DMG" -quiet

# Mounten
MOUNT_DIR="$(mktemp -d)"
hdiutil attach "$RW_DMG" -mountpoint "$MOUNT_DIR" -nobrowse -noverify -noautoopen -quiet

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
  sync
else
  echo "make-dmg: Finder-Styling nicht möglich (Headless/CI) – DMG enthält App, /Applications-Symlink und Hintergrundbild, aber keine vorgesetzten Icon-Positionen."
fi

hdiutil detach "$MOUNT_DIR" -quiet
MOUNT_DIR=""

# In komprimiertes, schreibgeschütztes DMG wandeln
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUT_DMG" -ov -quiet

# Optional signieren (ad-hoc "-" oder Developer-ID)
codesign --force --sign "$SIGN_IDENTITY" "$OUT_DMG" 2>/dev/null && \
  echo "make-dmg: DMG signiert ($SIGN_IDENTITY)" || \
  echo "make-dmg: DMG-Signatur übersprungen"

echo "make-dmg: erstellt $OUT_DMG"
