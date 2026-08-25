# KeystrokeQR (iOS)

SwiftUI-App für iPhone (iOS 17+, Portrait), die QR- und Barcodes scannt und den
Inhalt per WebSocket an die KeystrokeQR-Mac-App im lokalen Netzwerk sendet. Der
Mac wird automatisch via Bonjour (`_keystrokeqr._tcp`) gefunden; der Port kommt
immer aus der Bonjour-Auflösung. Die Verbindung ist Ende-zu-Ende verschlüsselt
und erfordert ein einmaliges Pairing (OTP-Code am Mac) — siehe
[`../docs/PROTOCOL-v2.md`](../docs/PROTOCOL-v2.md) (Protokoll v1:
[`../docs/PROTOCOL.md`](../docs/PROTOCOL.md)). Alle Namen/IDs sind in
[`../docs/BRANDING.md`](../docs/BRANDING.md) festgelegt.

> Der Xcode-Target-/Ordnername bleibt aus Kompatibilitätsgründen
> `QRKeyboardScanner`; nutzersichtbarer Anzeigename und alle Bundle-IDs lauten
> jedoch **KeystrokeQR** (siehe BRANDING.md).

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
Das Projekt liegt bewusst **ohne** `DEVELOPMENT_TEAM` im Repository; die
Bundle-IDs sind `de.timehrenfried.keystrokeqr` (App) bzw.
`de.timehrenfried.keystrokeqr.widgets` (Widget-Extension).

### Kommandozeile (ohne Signing, Simulator)

```sh
xcodebuild -project QRKeyboardScanner.xcodeproj \
  -scheme QRKeyboardScanner \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  build CODE_SIGNING_ALLOWED=NO
```

## Sprache & Lokalisierung (i18n)

- **Basissprache: Englisch (`en`)**, zusätzlich **Deutsch (`de`)**.
- Alle nutzersichtbaren SwiftUI-Strings laufen über den String Catalog
  [`Shared/Localizable.xcstrings`](Shared/Localizable.xcstrings) (Mitglied von
  App- und Widget-Target). Berechtigungs-/Anzeigename-Texte der Info.plist
  liegen in [`QRKeyboardScanner/InfoPlist.xcstrings`](QRKeyboardScanner/InfoPlist.xcstrings).
- `developmentRegion = en`, `knownRegions = en, de`. Neue Texte werden
  zweisprachig gepflegt (Englisch zuerst, Deutsch gleichwertig).

## Erstes Onboarding (First-Run)

Beim allerersten Start erscheint einmalig ein mehrstufiger Onboarding-Flow
([`QRKeyboardScanner/OnboardingView.swift`](QRKeyboardScanner/OnboardingView.swift))
im dunklen App-Design: Willkommen → Funktionsweise (lokal, verschlüsselt, kein
Cloud) → Berechtigungen (Kamera-Prompt wird hier kontextuell ausgelöst, lokales
Netzwerk angekündigt) → Kopplung. Persistenz über `@AppStorage`
(`didCompleteOnboarding`); Kamera-Zugriff und Bonjour-Discovery starten erst
nach Abschluss. Der Flow ist jederzeit über die Hilfe erneut aufrufbar
(„Einführung erneut anzeigen“).

## Benötigte Berechtigungen

| Berechtigung | Zweck |
| --- | --- |
| **Kamera** (`NSCameraUsageDescription`) | Scannen der QR-/Barcodes. Bei Ablehnung zeigt die App einen Hinweis mit Link in die Einstellungen. |
| **Lokales Netzwerk** (`NSLocalNetworkUsageDescription` + `NSBonjourServices = _keystrokeqr._tcp`) | Bonjour-Suche nach dem Mac und direkte WebSocket-Verbindung. iOS fragt beim ersten Scan-Start; bei Ablehnung wird kein Mac gefunden (nachträglich änderbar unter Einstellungen → Apps → KeystrokeQR → Lokales Netzwerk). |

## Funktionen

- Bildschirmfüllender Sucher, Status-Kapsel (Suche / Verbinde / Verbunden / Getrennt).
- Unterstützte Symbologien: QR, EAN-8/13, Code 128/39/93, PDF417, DataMatrix,
  Aztec, Interleaved 2/5, ITF-14, UPC-E.
- Bei Erkennung: haptisches Feedback, Sucher friert kurz ein, exakt 1 s Cooldown.
- Gelbe Outlines um alle aktuell erkannten Codes im Sucher (wie der
  System-Scanner), sanft nachgeführt, kurzes Fade-out beim Verlassen des Bilds.
- **Einmal-Übertragung:** Jeder Code wird nur einmal automatisch getippt. Beim
  erneuten Scannen desselben Codes erscheint stattdessen ein gelber Auslöser
  „Erneut senden“ zum bewussten Wiederholen. „Verlauf leeren“ (⟲) setzt die
  Liste zurück; bei App-Neustart wird sie automatisch geleert (keine Persistenz).
- Beste Rückkamera als virtuelles Device (Triple → DualWide → Dual → Wide):
  automatischer Linsenwechsel inkl. Makro bei nahen Codes; kontinuierlicher
  Autofokus mit Nahbereichs-Präferenz, **Tap-to-Focus** (gelber Rahmen) und
  **Pinch-to-Zoom** (bis 10x).
- Durchgehend dunkles Design inkl. dunklem Launch Screen und dunklem
  Lade-Zustand, bis die Kamera Bilder liefert.
- Toggles **Auto-Enter** / **Auto-Tab** (persistiert), Anzeige des zuletzt
  gescannten Texts, In-App-Hilfe.
- Automatischer Reconnect bei Verbindungsabriss; Auswahl-Liste, wenn mehrere
  Macs gefunden werden.
- Meldet der Mac `accessibility_denied`, zeigt die App einen deutlichen Hinweis.
- **Pairing:** Wird ein neuer, verschlüsselter Mac (`v=2`) gefunden, erscheint
  automatisch ein Pairing-Screen (6-stelliger OTP vom Mac-Menü „Gerät
  koppeln…“). Nach Erfolg verbindet sich die App automatisch und Ende-zu-Ende
  verschlüsselt; „Gekoppelte Macs verwalten“ (Hilfe) erlaubt das Entkoppeln.
  Reine v1-Hosts zeigen den Hinweis „Mac-App aktualisieren“.

## Schnellstart vom Sperrbildschirm

Die App bringt eine Widget-Extension (`QRKeyboardScannerWidgets`) und App
Intents mit; alle Wege öffnen die App direkt im Scanner (Deep-Link
`keystrokeqr://scan`):

- **Sperrbildschirm-Widget (iOS 17+):** Sperrbildschirm gedrückt halten →
  *Anpassen* → Sperrbildschirm → Widget-Bereich antippen → **KeystrokeQR**
  hinzufügen (rund oder rechteckig). Zusätzlich gibt es ein kleines
  Homescreen-Widget.
- **Sperrbildschirm-Schnelltasten / Kontrollzentrum (iOS 18+):** Beim
  Anpassen des Sperrbildschirms eine der unteren Schnelltasten
  (Taschenlampe/Kamera) durch die Steuerung **„QR-Code scannen“** ersetzen —
  oder die Steuerung ins Kontrollzentrum legen (Control Widget).
- **Action Button (iPhone 15 Pro+):** Einstellungen → *Action Button* →
  *Kurzbefehl* → **„QR-Code scannen“**.
- **Siri/Spotlight/Shortcuts:** Der App Intent „QR-Code scannen“ steht in der
  Shortcuts-App bereit; Siri-Phrase z. B. „Scan QR Code with KeystrokeQR“.

Technik: URL-Scheme `keystrokeqr` (`keystrokeqr://scan`), `StartScanIntent`
(AppIntent, `openAppWhenRun`) + `AppShortcutsProvider` im App-Target, Widget-
Extension mit Lock-Screen-/Homescreen-Widget (`.widgetURL`) und iOS-18-
ControlWidget (Bundle-ID `de.timehrenfried.keystrokeqr.widgets`, Deployment
iOS 17, ControlWidget `@available(iOS 18)`-gated).

## Version

`0.7.0` (`MARKETING_VERSION` in App- und Widget-Target, Debug + Release).
