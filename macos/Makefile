APP_NAME    := KeystrokeQR Host
BINARY      := QRKeyboardHost
BUILD_DIR   := .build
RELEASE_BIN := $(BUILD_DIR)/release/$(BINARY)
DIST_DIR    := dist
BUNDLE      := $(DIST_DIR)/$(APP_NAME).app
DMG         := $(DIST_DIR)/KeystrokeQR-Host.dmg
# Vorgeneriertes, eingechecktes Hintergrundbild (wie Support/AppIcon.icns) —
# so braucht `make dmg` (und die CI) KEIN ImageMagick. Neu erzeugen mit `make dmg-bg`.
DMG_BG      := Support/dmg-background.png
LANGS       := en de

# Signatur-Identität: Standard ist ad-hoc ("-"). Mit Apple-Developer-Account
# stattdessen z. B.:  make app SIGN_IDENTITY="Developer ID Application: Tim Ehrenfried (TEAMID)"
# (verfügbare Identitäten anzeigen: security find-identity -v -p codesigning)
SIGN_IDENTITY ?= -

.PHONY: build app icon dmg dmg-bg run clean

## Release-Binary bauen
build:
	swift build -c release

## App-Icon aus dem Master neu erzeugen (Support/AppIcon.icns)
icon:
	bash ./Support/make-icon.sh

## .app-Bundle bauen (wichtig für die Accessibility-Berechtigung pro App)
## Inklusive Lokalisierungen (en = Basissprache, de) in Contents/Resources/*.lproj.
app: build
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS"
	cp "$(RELEASE_BIN)" "$(BUNDLE)/Contents/MacOS/$(BINARY)"
	cp Support/Info.plist "$(BUNDLE)/Contents/Info.plist"
	mkdir -p "$(BUNDLE)/Contents/Resources"
	cp Support/AppIcon.icns "$(BUNDLE)/Contents/Resources/AppIcon.icns"
	@for lang in $(LANGS); do \
		mkdir -p "$(BUNDLE)/Contents/Resources/$$lang.lproj"; \
		cp Support/$$lang.lproj/*.strings "$(BUNDLE)/Contents/Resources/$$lang.lproj/"; \
	done
	codesign --force --options runtime --sign "$(SIGN_IDENTITY)" "$(BUNDLE)"
	@echo "Bundle erstellt: $(BUNDLE)"

## DMG-Hintergrundbild neu erzeugen (nur bei Design-Änderung; braucht ImageMagick)
dmg-bg:
	bash ./Support/make-dmg-background.sh "$(DMG_BG)"

## Gestyltes DMG „KeystrokeQR-Host.dmg" bauen (App links, /Applications rechts).
## Nutzt das eingecheckte $(DMG_BG) — kein ImageMagick zur Build-Zeit nötig.
dmg: app
	bash ./Support/make-dmg.sh "$(BUNDLE)" "$(APP_NAME)" "$(DMG)" "$(DMG_BG)" "$(SIGN_IDENTITY)"
	@echo "DMG erstellt: $(DMG)"

## App-Bundle bauen und starten
run: app
	open "$(BUNDLE)"

## Build-Artefakte entfernen
clean:
	swift package clean
	rm -rf "$(DIST_DIR)"
