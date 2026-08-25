# Changelog

Alle nennenswerten Änderungen an diesem Projekt werden hier dokumentiert.
Format nach [Keep a Changelog](https://keepachangelog.com/de/1.1.0/), Versionierung nach [SemVer](https://semver.org/lang/de/).

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
