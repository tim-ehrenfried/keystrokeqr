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

# ASC-API-Key für die Notarisierung (`make notarize`, siehe docs/RELEASE-PHASE.md
# Phase 4). KEINE Defaults mit echten Werten — nur beim Aufruf setzen, z. B.:
#   make notarize ASC_KEY_PATH=~/.secrets/AuthKey_XXXXXXXXXX.p8 \
#                 ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
ASC_KEY_PATH  ?=
ASC_KEY_ID    ?=
ASC_ISSUER_ID ?=

# Branding-Gating (siehe Sources/QRKeyboardHost/BrandingConfig.swift):
# Standard (OFFICIAL=0) ist der NEUTRALE Community-Build — ohne persönliche
# Kontakt-/Infrastruktur-Referenzen (keine Mail, keine Landing-Page-/iOS-URL,
# keine QR-Promo-Karte). Offizielle Builds (unsere CI/Signierung) bauen mit
#   make build|app|dmg OFFICIAL=1
# → swift build … -Xswiftc -DOFFICIAL_BUILD, wodurch BrandingConfig die
# offiziellen Werte einkompiliert. Der GitHub-Repo-Link bleibt ungegated.
OFFICIAL ?= 0
ifeq ($(OFFICIAL),1)
SWIFT_BUILD_FLAGS := -Xswiftc -DOFFICIAL_BUILD
else
SWIFT_BUILD_FLAGS :=
endif

.PHONY: build app icon dmg dmg-bg notarize run clean

## Release-Binary bauen (OFFICIAL=1 → offizielles Branding, s. o.)
build:
	swift build -c release $(SWIFT_BUILD_FLAGS)

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
	@# Secure Timestamp (--timestamp): von Apple für Developer-ID-Signaturen
	@# verlangt (Notarisierung scheitert sonst) — bei ad-hoc ("-") wird
	@# Timestamping nicht unterstützt und codesign würde fehlschlagen, daher
	@# nur setzen wenn eine echte Signing-Identität verwendet wird.
	@if [ "$(SIGN_IDENTITY)" = "-" ]; then \
		codesign --force --options runtime --sign "$(SIGN_IDENTITY)" "$(BUNDLE)"; \
	else \
		codesign --force --options runtime --timestamp --sign "$(SIGN_IDENTITY)" "$(BUNDLE)"; \
	fi
	@echo "Bundle erstellt: $(BUNDLE)"

## DMG-Hintergrundbild neu erzeugen (nur bei Design-Änderung; braucht ImageMagick)
dmg-bg:
	bash ./Support/make-dmg-background.sh "$(DMG_BG)"

## Gestyltes DMG „KeystrokeQR-Host.dmg" bauen (App links, /Applications rechts).
## Nutzt das eingecheckte $(DMG_BG) — kein ImageMagick zur Build-Zeit nötig.
dmg: app
	bash ./Support/make-dmg.sh "$(BUNDLE)" "$(APP_NAME)" "$(DMG)" "$(DMG_BG)" "$(SIGN_IDENTITY)" "Support/AppIcon.icns"
	@echo "DMG erstellt: $(DMG)"

## Fertiges DMG bei Apple notarisieren (setzt ein mit der Developer-ID
## signiertes DMG voraus, s. "dmg" + SIGN_IDENTITY) und das Ticket aufkleben.
## Braucht ASC_KEY_PATH/ASC_KEY_ID/ASC_ISSUER_ID (s. o.) — normalerweise nur
## von der Release-Pipeline aufgerufen (siehe docs/RELEASE-PHASE.md Phase 4).
## Lokal NICHT ohne Grund mit echten Secrets aufrufen.
notarize:
	@test -n "$(ASC_KEY_PATH)" || { echo "notarize: ASC_KEY_PATH fehlt" >&2; exit 1; }
	@test -n "$(ASC_KEY_ID)" || { echo "notarize: ASC_KEY_ID fehlt" >&2; exit 1; }
	@test -n "$(ASC_ISSUER_ID)" || { echo "notarize: ASC_ISSUER_ID fehlt" >&2; exit 1; }
	@test -f "$(DMG)" || { echo "notarize: $(DMG) nicht gefunden (erst 'make dmg' ausführen)" >&2; exit 1; }
	xcrun notarytool submit "$(DMG)" \
		--key "$(ASC_KEY_PATH)" \
		--key-id "$(ASC_KEY_ID)" \
		--issuer "$(ASC_ISSUER_ID)" \
		--wait
	xcrun stapler staple "$(DMG)"
	@echo "DMG notarisiert + Ticket aufgeklebt: $(DMG)"

## App-Bundle bauen und starten
run: app
	open "$(BUNDLE)"

## Build-Artefakte entfernen
clean:
	swift package clean
	rm -rf "$(DIST_DIR)"
