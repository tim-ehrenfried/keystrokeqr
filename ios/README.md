# QR-Keyboard Scanner (iOS)

SwiftUI-App für iPhone (iOS 17+, Portrait), die QR- und Barcodes scannt und den
Inhalt per WebSocket an die QR-Keyboard-Mac-App im lokalen WLAN sendet. Der Mac
wird automatisch via Bonjour (`_qr-keyboard._tcp`) gefunden; der Port kommt
immer aus der Bonjour-Auflösung. Protokoll: siehe [`../docs/PROTOCOL.md`](../docs/PROTOCOL.md).

## Build & Run

### Xcode

1. `QRKeyboardScanner.xcodeproj` in Xcode (16 oder neuer) öffnen.
2. Scheme **QRKeyboardScanner** ist als shared Scheme enthalten und wird
   automatisch angeboten.
3. Ziel wählen (Simulator oder iPhone) und **Run** (⌘R).

> **Hinweis Simulator:** Der Simulator hat keine Kamera — Scannen funktioniert
> nur auf einem echten iPhone. Bonjour/WebSocket funktionieren im Simulator.

### Echtes iPhone (Signing)

Für den Lauf auf einem echten Gerät muss in Xcode ein Signing-Team gewählt
werden: Target **QRKeyboardScanner** → Tab **Signing & Capabilities** →
**Team** auswählen (persönliches Apple-ID-Team genügt für die Entwicklung).
Das Projekt liegt bewusst ohne `DEVELOPMENT_TEAM` im Repository.

### Kommandozeile (ohne Signing, Simulator)

```sh
xcodebuild -project QRKeyboardScanner.xcodeproj \
  -target QRKeyboardScanner \
  -sdk iphonesimulator -configuration Debug \
  build CODE_SIGNING_ALLOWED=NO
```

## Benötigte Berechtigungen

| Berechtigung | Zweck |
| --- | --- |
| **Kamera** (`NSCameraUsageDescription`) | Scannen der QR-/Barcodes. Bei Ablehnung zeigt die App einen Hinweis mit Link in die Einstellungen. |
| **Lokales Netzwerk** (`NSLocalNetworkUsageDescription` + `NSBonjourServices = _qr-keyboard._tcp`) | Bonjour-Suche nach dem Mac und direkte WebSocket-Verbindung. iOS fragt beim ersten Start; bei Ablehnung wird kein Mac gefunden (nachträglich änderbar unter Einstellungen → Apps → QR-Keyboard Scanner → Lokales Netzwerk). |

## Funktionen

- Bildschirmfüllender Sucher, Status-Kapsel (Suche / Verbinde / Verbunden / Getrennt).
- Unterstützte Symbologien: QR, EAN-8/13, Code 128/39/93, PDF417, DataMatrix,
  Aztec, Interleaved 2/5, ITF-14, UPC-E.
- Bei Erkennung: haptisches Feedback, Sucher friert kurz ein, exakt 1 s Cooldown.
- Toggles **Auto-Enter** / **Auto-Tab** (persistiert), Anzeige des zuletzt
  gescannten Texts, In-App-Hilfe.
- Automatischer Reconnect bei Verbindungsabriss; Auswahl-Liste, wenn mehrere
  Macs gefunden werden.
- Meldet der Mac `accessibility_denied`, zeigt die App einen deutlichen Hinweis
  („Mac: Bedienungshilfen-Berechtigung fehlt“).
