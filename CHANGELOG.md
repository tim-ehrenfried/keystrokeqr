# Changelog

Alle nennenswerten Änderungen an diesem Projekt werden hier dokumentiert.
Format nach [Keep a Changelog](https://keepachangelog.com/de/1.1.0/), Versionierung nach [SemVer](https://semver.org/lang/de/).

## [0.10.0] – 2026-08-25

### Changed
- **macOS – ein Fenster statt drei**: Kontrollpanel, Hilfe und Über sind jetzt ein Fenster mit interner Navigation (Zurück-Button); das Fenster öffnet exakt in Inhaltsgröße (kein Scrollen). „Einführung anzeigen" ist ein dezenter grauer Button oben rechts (kein blauer Link mehr); die Links in Über/Hilfe sind Icon-Buttons (GitHub/E-Mail/Doku) wie in der iOS-App.
- **macOS – Pairing**: bei Ablauf des Codes wird automatisch ein neuer erzeugt (kein „Neuen Code"-Button mehr), Countdown zurückgesetzt, Hinweis „Code abgelaufen – neuer Code erzeugt".

### Fixed
- **iOS – Pairing-Screen war nach dem Schließen nur per App-Neustart wieder erreichbar**: Der Screen poppte durch die laufende Discovery in einer Schleife auf; der einzige Ausweg war Neustart. Jetzt merkt sich die App eine bewusste Ablehnung (kein automatisches Wieder-Aufpoppen) UND bietet einen jederzeit sichtbaren Weg zurück — ein „Mac koppeln"-Button in der Scanner-Ansicht (sobald ein Mac gefunden, aber nicht verbunden) sowie die Mac-Auswahlliste öffnen den Pairing-Screen erneut.

## [0.9.0] – 2026-08-25

### Added
- **macOS – KeystrokeQR-Panel (Kontrollzentrum)**: Ein gestyltes Fenster bündelt die bisherigen Menüpunkte — Verbindungsstatus, **live sichtbarer Bedienungshilfen-Status** (grünes ✓ „Aktiviert" / rotes ✗, aktualisiert sich ohne Neustart nach dem Erteilen), gekoppelte Geräte (mit „Entfernen"), Kopplung, Tippgeschwindigkeit, Hilfe, Über, Einführung. Das Menüleisten-Menü ist dadurch schlank (inkl. ✓/✗-Kurzstatus).
- **macOS – In-App-Hilfe** (Kurzanleitung + Troubleshooting + Repo/Docs-Links) und **Über/About** (Version dynamisch, © 2026 Tim Ehrenfried, mail@tim-ehrenfried.de, GitHub, MIT).
- **iOS – Mehrere Macs & Mac-Wechsel**: Liste aller gefundenen Macs mit Status-Badges (Verbunden/Gekoppelt/Neu/Aktualisieren), jederzeit über einen Button erreichbar; aktiver Wechsel trennt sauber die aktuelle Verbindung (kein Session-Key-Leak zwischen Macs) und verbindet/koppelt zum gewählten Mac.

### Fixed
- **Nach „Gerät entfernen" am Mac war keine (erneute) Verbindung möglich**: Das `session_error`/`not_paired`-Frame ging durch das sofortige Schließen der Verbindung verloren, sodass das iPhone in einer stillen Endlos-Reconnect-Schleife hing statt Neu-Pairing anzubieten.
  - **macOS**: `not_paired`/`bad_session` werden jetzt erst **nach bestätigtem Absenden** geschlossen (`closeAfterSend`), erreichen den Client also zuverlässig; „Gerät entfernen" trennt zudem sofort die aktive Sitzung.
  - **iOS**: unterscheidet host-seitiges Entkoppeln von transientem Netzabriss (Handshake-Fenster-Heuristik als Fallback) → löscht bei `not_paired` den veralteten PSK und bietet direkt Neu-Pairing an, statt endlos zu suchen.

## [0.8.0] – 2026-08-25

### Added
- **macOS – einstellbare Tippgeschwindigkeit**: Menü „Tippgeschwindigkeit" (Schnell / Normal / Langsam) steuert Chunk-Größe und Pause im KeyInjector, damit sich bei viel Text im Zielfeld nichts verschluckt; Wahl persistent, greift sofort.
- **macOS – Erst-Start-Onboarding**: gestyltes Willkommensfenster beim ersten Start (Funktionsweise, Bedienungshilfen-Button, „Gerät koppeln…"), erneut über „Einführung anzeigen" aufrufbar.

### Changed
- **Pairing-Fenster (macOS) neu gestaltet**: dunkler Onboarding-Look, Code in Ziffernkästchen, Countdown-Balken, Wortmarke; schließt bei Erfolg automatisch nach ~1,5 s.
- **iOS – Pairing-Screen** schließt bei Erfolg automatisch; klare Status-/Fehlerzeile mit Spinner.

### Fixed
- **Falscher Kopplungscode führte zu Timeout / kryptischem Fehler**: Der Host verwarf den OTP, erzeugte aber keinen neuen; der Client lief in einen Timeout, weil das `pair_error`-Frame beim sofortigen Verbindungsabbruch verloren ging.
  - **macOS**: bei falschem Code wird sofort automatisch ein **neuer OTP** erzeugt (Fenster bleibt offen, freundlicher Hinweis, Countdown zurückgesetzt); `pair_ok`/`pair_error` werden erst **nach bestätigtem Absenden** geschlossen (kein verworfenes Frame mehr), inkl. „Neuen Code erzeugen" bei Ablauf.
  - **iOS**: reagiert sofort auf `pair_error` (klarer „Falscher Code"-Hinweis, Feld-Reset, Reconnect gegen den neuen Code) mit Grace-Period, sodass der Fehler den Verbindungsabbruch immer schlägt; echter Timeout nur noch als letzter Ausweg.

## [0.7.0] – 2026-08-25

### Changed
- **Rebrand auf „KeystrokeQR"**: iOS-App → **KeystrokeQR**, macOS-Menüleisten-App → **KeystrokeQR Host**. Bundle-IDs neu: `de.timehrenfried.keystrokeqr` (App), `.widgets` (Widget), `.host` (Mac). Bonjour-Service-Typ `_qr-keyboard._tcp` → `_keystrokeqr._tcp`, URL-Scheme `qrkeyboard://` → `keystrokeqr://`, Keychain-Services angepasst. GitHub-Repo + lokaler Ordner → `keystrokeqr`. Verbindliche Namensspec: [docs/BRANDING.md](docs/BRANDING.md).
  - **Breaking**: wegen geänderter Service-Typen/Bundle-IDs müssen bestehende v0.6.x-Kopplungen einmal neu durchgeführt und die Apps gemeinsam aktualisiert werden.

### Added
- **Internationalisierung (i18n)**: Englisch als Basissprache, Deutsch zusätzlich — beide Apps vollständig lokalisiert (iOS via String Catalog `Localizable.xcstrings`/`InfoPlist.xcstrings`, 103 Keys; macOS via `en.lproj`/`de.lproj`).
- **iOS – First-Run-Onboarding**: vierseitiger Einführungsflow (Willkommen / Funktionsweise / Berechtigungen mit kontextuellem Kamera-Prompt / Kopplung), einmalig beim ersten Start, erneut aufrufbar über die Hilfe.
- **macOS – gestylter DMG-Installer**: `make dmg` erzeugt `KeystrokeQR-Host.dmg` (Fenster-Hintergrundbild, App + /Applications-Symlink); der Release-Workflow lädt `KeystrokeQR-Host-macOS.dmg` als Asset hoch (löst das ZIP ab).
- **Neue App-Icons** (iOS + macOS) im KeystrokeQR-Motiv (QR-Viewfinder + Keystroke-/Tasten-Akzent, gelbe Scan-Linie), stilistisch konsistent über beide Plattformen.

## [0.6.1] – 2026-08-25

### Fixed
- **iOS – „Mac-App veraltet" trotz v0.6.0-Host**: `NWBrowser` liefert den Bonjour-TXT-Record in Browse-Ergebnissen nicht zuverlässig mit (oft `.none`), wodurch der Client jeden Mac fälschlich als v1 einstufte und den Pairing-Screen unterdrückte. Ein Host gilt jetzt nur noch als veraltet, wenn er sich **explizit** als `v=1` meldet; fehlender Record oder `v=2` → als v2 behandelt (die Version wird beim Handshake final geprüft). Damit erscheint der Kopplungs-Dialog korrekt.

## [0.6.0] – 2026-08-25

### Added
- **Ende-zu-Ende-Verschlüsselung + Geräte-Pairing (Protokoll v2)**: Jede Verbindung ist jetzt verschlüsselt und beidseitig authentifiziert. Ein iPhone muss einmalig gekoppelt werden — der Mac zeigt im Menü unter „Gerät koppeln…" einen 6-stelligen OTP (90 s), den das iPhone einmalig einträgt. Dahinter: Curve25519-Schlüsselaustausch mit OTP-HMAC-Bestätigung → langlebiger PSK (beidseitig im Keychain, nie über das Netz), pro Sitzung ein frischer HKDF-Sessionkey, alle Scan-/Ack-Frames als ChaChaPoly-AEAD mit Replay-Schutz (CryptoKit). Spezifikation: [docs/PROTOCOL-v2.md](docs/PROTOCOL-v2.md).
- **Mac – Geräteverwaltung**: Menü listet gekoppelte iPhones (mit Pairing-Datum) samt „Entfernen" (widerruft PSK sofort, trennt laufende Sitzung); Status „N gekoppelt · M verbunden".
- **iOS – Pairing-UI**: Setup-/Pairing-Screen (Mac wählen, OTP eingeben) und „Gekoppelte Macs verwalten"; Hinweis-Banner, wenn ein gefundener Mac noch v1 (< 0.6.0) läuft.

### Changed
- **Breaking**: Protokoll v2 löst v1 ab (Bonjour-TXT `v=2`); ein v2-Host akzeptiert nur v2-Clients und umgekehrt. Mac- und iOS-App gemeinsam aktualisieren.

### Security
- Schließt die offenen SECURITY.md-Findings **LAN-Keystroke-Injection**, **Klartext-Sniffing** und **Host-Spoofing** (nur gekoppelte, per PSK authentifizierte Geräte kommen durch). Restrisiko der OTP-Entropie (~20 bit, ein Versuch pro 90-s-Fenster) dokumentiert.

## [0.5.1] – 2026-08-25

### Fixed
- **iOS – Overlay-Randabstand endgültig**: Die Bedienleisten-Zeile lief wegen der nicht schrumpfbaren Toggles (`.fixedSize()`) über die Bildschirmbreite hinaus und zog Auslöser-Kapsel und Leiste randlos — Toggles jetzt als Chip mit skalier-/kürzbarem Label, Zeilen-Spacing reduziert. Im Simulator pixelgenau verifiziert (16 pt Seitenränder, 12 pt über dem Home-Indicator).
- Versehentliche Ordner-Umbenennung von `ios/Shared/` rückgängig gemacht (die App hatte einen Scan-Payload in ein fokussiertes Xcode-Umbenennen-Feld getippt — Praxisbeleg für das in SECURITY.md beschriebene Injection-Risiko und den Pairing-Plan).

### Added
- `docs/PLAN-SECURITY-DISTRIBUTION.md`: Plan für TLS-PSK-Verschlüsselung + einmaliges OTP-Pairing sowie CI/CD-Distribution (App Store/TestFlight + notarisiertes DMG). Nur Planung, keine Umsetzung.

## [0.5.0] – 2026-08-25

### Added
- **iOS – Code-Outlines**: gelbe, sanft nachgeführte Rahmen um alle aktuell erkannten Codes (CAShapeLayer auf dem Preview, perspektivische Ecken via `transformedMetadataObject`, Fade-out beim Verlassen des Bilds) — wie beim System-QR-Scanner.
- **iOS – Hilfe „Über"-Abschnitt**: App-Version/Build dynamisch, © 2026 Tim Ehrenfried, Kontakt mail@tim-ehrenfried.de, GitHub-Link.
- **App-Icons** für iOS (Asset Catalog, 1024er Single-Size) und macOS (AppIcon.icns im Bundle): dunkler Verlauf, weißes QR-Viewfinder-Motiv, gelbe Scan-Linie.
- **GitHub-Infrastruktur**: CI-Workflow (macOS-Host-Build + iOS-Simulator-Build) und Release-Workflow (Tag `v*` → `QR-Keyboard-Host-macOS.zip` als GitHub-Release), `SECURITY.md` (Threat Model, Empfehlungen, Responsible Disclosure), `docs/INSTALL.md` (Endnutzer-Installation inkl. Gatekeeper).

### Fixed
- **iOS – Layout**: Overlays (Status, Auslöser, Bedienleiste) klebten randlos an den Bildschirmkanten; jetzt durchgängige 16-pt-Margins, Bedienleiste als abgerundete Karte, Safe-Area/Home-Indicator respektiert.

### Security
- **macOS – DoS-Schutz**: WebSocket-Frames auf 64 KiB und `text` auf 8192 UTF-16-Einheiten begrenzt; Überschreitung → neues Ack `payload_too_large` statt minutenlangem „Volltippen" (PROTOCOL.md ergänzt).

## [0.4.0] – 2026-08-25

### Added
- **iOS – Einmal-Übertragung**: Jeder Code wird pro App-Sitzung nur einmal automatisch gesendet. Wird ein bereits gesendeter Code erneut erkannt, erscheint stattdessen ein gelber Auslöser „Erneut senden" (nur solange der Code im Bild ist, blendet nach 2,5 s aus) — erst ein Druck sendet erneut. Dezente Wiederholungs-Haptik einmal pro Sichtung, framerate-entprellt. Dazu „Verlauf leeren"-Button (mit Bestätigung); das Sent-Set ist bewusst nicht persistiert und leert sich bei App-Neustart.

## [0.3.0] – 2026-08-25

### Added
- **iOS – Kamera**: virtuelle Kamera mit automatischem Linsen-/Makro-Wechsel (Triple → DualWide → Dual → Weitwinkel-Fallback), korrekter Start-Zoom (kein Ultraweitwinkel-Start), Continuous-Autofocus mit Nah-Restriktion + Auto-Belichtung + Subject-Area-Reset, **Tap-to-Focus** mit Fokus-Rahmen und **Pinch-to-Zoom** (bis 10x).
- **iOS – Dunkler Launch-/Ladezustand**: schwarzer Launch Screen (UILaunchScreen + Asset-Farbe), schwarzes „Kamera wird gestartet…"-Overlay bis die Session läuft, dunkler Kamera-verweigert-Screen.

### Fixed
- **iOS-18-Sperrbildschirm-Steuerung öffnete nichts**: Control-Intent wird vom System im App-Prozess ausgeführt, existierte aber nur in der Widget-Extension → `StartScanIntent` liegt jetzt in `Shared/` mit Membership in App **und** Extension; fehleranfällige `OpenURLIntent`-Variante (iOS-18.0-Bug) entfernt. ControlWidget, Action Button, Shortcuts und Siri laufen über denselben Intent.

## [0.2.0] – 2026-08-25

### Added
- **iOS – Schnellstart vom Sperrbildschirm**: Widget-Extension `QRKeyboardScannerWidgets` mit Lock-Screen-Widget (accessoryCircular/-Rectangular, systemSmall) via Deep-Link `qrkeyboard://scan`; iOS-18-ControlWidget für Sperrbildschirm-Schnelltasten und Kontrollzentrum; App Intent „QR-Code scannen" + App Shortcuts (Siri, Spotlight, Kurzbefehle-App, Action Button); URL-Scheme `qrkeyboard` mit robustem `.onOpenURL`-Handler inkl. Cooldown-Reset.
- **Doku**: `docs/SETUP.md` — Schritt-für-Schritt vom Apple-Developer-Account bis zum laufenden System (Signing, Entwicklermodus, Berechtigungen, Sperrbildschirm-Einrichtung, Troubleshooting); In-App-Hilfe und READMEs entsprechend erweitert.

### Changed
- **macOS – Makefile**: neue Variable `SIGN_IDENTITY` (Standard ad-hoc) für stabile Signatur mit Developer-Zertifikat; Signierung mit Hardened Runtime (`--options runtime`).

## [0.1.0] – 2026-08-25

### Added
- **macOS-Host** (`macos/`): Menüleisten-App mit lokalem WebSocket-Server (Network.framework, Port 8080 mit Fallback), Bonjour-Advertising `_qr-keyboard._tcp`, Key-Injection via CGEvent (Unicode-sicher, layout-unabhängig), optional Tab/Enter nach dem Text, Accessibility-Statusanzeige inkl. Direktlink in die Systemeinstellungen, Makefile-Build zum `.app`-Bundle.
- **iOS-Scanner** (`ios/`): SwiftUI-App mit Vollbild-Kamera-Sucher (AVFoundation, QR + gängige Barcode-Typen), automatischer Mac-Suche via Bonjour (keine IP-Eingabe), WebSocket-Versand, haptischem Feedback, 1-s-Scan-Cooldown, Auto-Enter-/Auto-Tab-Schaltern (persistent), automatischem Reconnect und In-App-Hilfe.
- **Protokoll-Spezifikation** `docs/PROTOCOL.md` (Bonjour + WebSocket + JSON, Ack mit Fehlercodes).
- Dokumentation: Root-README, Komponenten-READMEs mit Accessibility-Anleitung, MIT-Lizenz.
