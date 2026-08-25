APP_NAME    := QR Keyboard Host
BINARY      := QRKeyboardHost
BUILD_DIR   := .build
RELEASE_BIN := $(BUILD_DIR)/release/$(BINARY)
DIST_DIR    := dist
BUNDLE      := $(DIST_DIR)/$(APP_NAME).app

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
	codesign --force --sign - "$(BUNDLE)"
	@echo "Bundle erstellt: $(BUNDLE)"

## App-Bundle bauen und starten
run: app
	open "$(BUNDLE)"

## Build-Artefakte entfernen
clean:
	swift package clean
	rm -rf "$(DIST_DIR)"
