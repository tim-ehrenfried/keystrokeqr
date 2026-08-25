APP_NAME    := QR Keyboard Host
BINARY      := QRKeyboardHost
BUILD_DIR   := .build
RELEASE_BIN := $(BUILD_DIR)/release/$(BINARY)
DIST_DIR    := dist
BUNDLE      := $(DIST_DIR)/$(APP_NAME).app

# Signatur-Identität: Standard ist ad-hoc ("-"). Mit Apple-Developer-Account
# stattdessen z. B.:  make app SIGN_IDENTITY="Developer ID Application: Tim Ehrenfried (TEAMID)"
# (verfügbare Identitäten anzeigen: security find-identity -v -p codesigning)
SIGN_IDENTITY ?= -

.PHONY: build app run clean

## Release-Binary bauen
build:
	swift build -c release

## .app-Bundle bauen (wichtig für die Accessibility-Berechtigung pro App)
app: build
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS"
	cp "$(RELEASE_BIN)" "$(BUNDLE)/Contents/MacOS/$(BINARY)"
	cp Support/Info.plist "$(BUNDLE)/Contents/Info.plist"
	mkdir -p "$(BUNDLE)/Contents/Resources"
	cp Support/AppIcon.icns "$(BUNDLE)/Contents/Resources/AppIcon.icns"
	codesign --force --options runtime --sign "$(SIGN_IDENTITY)" "$(BUNDLE)"
	@echo "Bundle erstellt: $(BUNDLE)"

## App-Bundle bauen und starten
run: app
	open "$(BUNDLE)"

## Build-Artefakte entfernen
clean:
	swift package clean
	rm -rf "$(DIST_DIR)"
